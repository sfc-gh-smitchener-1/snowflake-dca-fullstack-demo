#!/usr/bin/env python3
"""
md_to_docx.py — Convert markdown with Mermaid diagrams to DOCX for Google Docs.

Extracts Mermaid code blocks, renders them to PNG (via mmdc or mermaid.ink API),
replaces the code blocks with image references, and runs pandoc to produce DOCX.

Usage:
    python3 md_to_docx.py --input README.md --output README.docx
    python3 md_to_docx.py --input README.md --use-api --keep-images
    python3 md_to_docx.py --check
"""

import argparse
import base64
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path


MERMAID_BLOCK_RE = re.compile(
    r"```mermaid\s*\n(.*?)```", re.DOTALL
)


def check_dependencies():
    """Check for required and optional dependencies."""
    pandoc = shutil.which("pandoc")
    mmdc = shutil.which("mmdc")

    print("Dependency check:")
    print(f"  pandoc: {'FOUND — ' + pandoc if pandoc else 'NOT FOUND (required)'}")
    print(f"  mmdc:   {'FOUND — ' + mmdc if mmdc else 'not found (optional — will use mermaid.ink API)'}")

    if not pandoc:
        print("\nInstall pandoc:")
        print("  macOS:  brew install pandoc")
        print("  Linux:  apt install pandoc")
        print("  Other:  https://pandoc.org/installing.html")
        return False

    return True


def render_mermaid_mmdc(diagram_text, output_path, bg_color="white", theme="default"):
    """Render a Mermaid diagram to PNG using mmdc (mermaid-cli)."""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".mmd", delete=False) as f:
        f.write(diagram_text)
        mmd_path = f.name

    try:
        cmd = [
            "mmdc",
            "-i", mmd_path,
            "-o", output_path,
            "-b", bg_color,
            "-t", theme,
            "--scale", "2",
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode != 0:
            raise RuntimeError(f"mmdc failed: {result.stderr}")
        return True
    finally:
        os.unlink(mmd_path)


def render_mermaid_api(diagram_text, output_path, bg_color="white", theme="default"):
    """Render a Mermaid diagram to PNG using the kroki.io API via curl."""
    import json

    url = "https://kroki.io/mermaid/png"
    payload = json.dumps({"diagram_source": diagram_text})

    cmd = [
        "curl", "-s", "-f",
        "-X", "POST", url,
        "-H", "Content-Type: application/json",
        "-o", output_path,
        "-d", payload,
        "--max-time", "60",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=90)
    if result.returncode != 0:
        raise RuntimeError(f"kroki.io API request failed (curl exit {result.returncode}): {result.stderr}")

    if not os.path.exists(output_path) or os.path.getsize(output_path) == 0:
        raise RuntimeError("kroki.io returned empty response")

    return True


def convert(input_path, output_path, bg_color="white", theme="default",
            use_api=False, keep_images=False, image_dir=None):
    """Convert a markdown file with Mermaid diagrams to DOCX."""
    input_path = Path(input_path).resolve()
    output_path = Path(output_path).resolve()

    if not input_path.exists():
        print(f"Error: input file not found: {input_path}", file=sys.stderr)
        sys.exit(1)

    if not shutil.which("pandoc"):
        print("Error: pandoc is required but not found. Install it first.", file=sys.stderr)
        sys.exit(1)

    has_mmdc = shutil.which("mmdc") is not None
    render_method = "kroki.io API"
    if has_mmdc and not use_api:
        render_method = "mmdc (local)"

    # Set up image directory
    if image_dir:
        img_dir = Path(image_dir).resolve()
        img_dir.mkdir(parents=True, exist_ok=True)
        tmp_dir = None
    else:
        tmp_dir = tempfile.mkdtemp(prefix="md_to_gdoc_")
        img_dir = Path(tmp_dir)

    try:
        content = input_path.read_text(encoding="utf-8")

        # Find all mermaid blocks
        blocks = list(MERMAID_BLOCK_RE.finditer(content))
        diagram_count = len(blocks)

        if diagram_count == 0:
            print("No Mermaid diagrams found. Converting markdown directly.")
        else:
            print(f"Found {diagram_count} Mermaid diagram(s). Rendering...")

        # Render each block and build replacement map
        modified = content
        for i, match in enumerate(reversed(blocks), 1):
            idx = diagram_count - i  # 0-based index for naming
            diagram_text = match.group(1).strip()
            img_name = f"diagram_{idx:02d}.png"
            img_path = str(img_dir / img_name)

            try:
                if has_mmdc and not use_api:
                    render_mermaid_mmdc(diagram_text, img_path, bg_color, theme)
                else:
                    render_mermaid_api(diagram_text, img_path, bg_color, theme)
                print(f"  [{idx + 1}/{diagram_count}] Rendered {img_name}")
            except RuntimeError as e:
                print(f"  [{idx + 1}/{diagram_count}] FAILED: {e}", file=sys.stderr)
                # Replace with a placeholder instead of image
                replacement = f"\n\n> **[Diagram {idx + 1} failed to render]**\n\n"
                modified = modified[:match.start()] + replacement + modified[match.end():]
                continue

            # Replace mermaid block with image reference
            replacement = f"\n\n![Diagram {idx + 1}]({img_path})\n\n"
            modified = modified[:match.start()] + replacement + modified[match.end():]

        # Write modified markdown to temp file
        tmp_md = img_dir / "converted.md"
        tmp_md.write_text(modified, encoding="utf-8")

        # Run pandoc
        cmd = [
            "pandoc",
            str(tmp_md),
            "-o", str(output_path),
            f"--resource-path={img_dir}",
            "--standalone",
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        if result.returncode != 0:
            print(f"Error: pandoc failed: {result.stderr}", file=sys.stderr)
            sys.exit(1)

        # Copy images to keep directory if requested
        if keep_images and tmp_dir:
            keep_dir = output_path.parent / f"{output_path.stem}_images"
            keep_dir.mkdir(exist_ok=True)
            for png in img_dir.glob("diagram_*.png"):
                shutil.copy2(png, keep_dir / png.name)
            print(f"  Images saved to: {keep_dir}")

        print(f"\nConversion complete:")
        print(f"  Input:    {input_path}")
        print(f"  Output:   {output_path}")
        print(f"  Diagrams: {diagram_count} rendered to PNG")
        print(f"  Method:   {render_method}")
        print(f"\nImport to Google Docs:")
        print(f"  1. Open Google Docs")
        print(f"  2. File > Open > Upload tab")
        print(f"  3. Select {output_path.name}")

    finally:
        if tmp_dir and not keep_images:
            shutil.rmtree(tmp_dir, ignore_errors=True)


def main():
    parser = argparse.ArgumentParser(
        description="Convert markdown with Mermaid diagrams to DOCX for Google Docs"
    )
    parser.add_argument("--check", action="store_true",
                        help="Check dependencies and exit")
    parser.add_argument("--input", "-i", type=str,
                        help="Input markdown file")
    parser.add_argument("--output", "-o", type=str,
                        help="Output DOCX file (default: <input_stem>.docx)")
    parser.add_argument("--bg-color", default="white",
                        help="Background color for diagrams (default: white)")
    parser.add_argument("--theme", default="default",
                        choices=["default", "dark", "forest", "neutral"],
                        help="Mermaid theme (default: default)")
    parser.add_argument("--use-api", action="store_true",
                        help="Force mermaid.ink API even if mmdc is installed")
    parser.add_argument("--keep-images", action="store_true",
                        help="Keep rendered PNG images after conversion")
    parser.add_argument("--image-dir", type=str,
                        help="Directory for rendered diagram images")

    args = parser.parse_args()

    if args.check:
        ok = check_dependencies()
        sys.exit(0 if ok else 1)

    if not args.input:
        parser.error("--input is required (or use --check to verify dependencies)")

    output = args.output
    if not output:
        output = str(Path(args.input).with_suffix(".docx"))

    convert(
        input_path=args.input,
        output_path=output,
        bg_color=args.bg_color,
        theme=args.theme,
        use_api=args.use_api,
        keep_images=args.keep_images,
        image_dir=args.image_dir,
    )


if __name__ == "__main__":
    main()
