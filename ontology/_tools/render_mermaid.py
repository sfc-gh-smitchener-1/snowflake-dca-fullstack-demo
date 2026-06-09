#!/usr/bin/env python3
"""Extract Mermaid diagrams from the Snowflake Ontology reference doc, render
them to PNG via mmdc, and rewrite the markdown so each Mermaid block becomes
an image reference. Canonical mermaid source is preserved as a sibling .mmd
file in diagrams/ so re-rendering after edits is trivial.

Configuration is via the slug map and the curated DEFAULT_FILES list.

Usage:
    python3 render_mermaid.py                       # convert the curated set
    python3 render_mermaid.py path/to/file.md       # convert a single file
    python3 render_mermaid.py --mmd-only            # re-render only .mmd files
    python3 render_mermaid.py --strip-source-comments  # remove old comment blocks
"""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

MERMAID_FENCE_RE = re.compile(
    r"^([ \t]*)```mermaid[ \t]*\n(.*?)\n[ \t]*```[ \t]*$",
    re.DOTALL | re.MULTILINE,
)

SLUGS_BY_FILE: dict[str, list[str]] = {
    "README.md": [
        "ont-l0-marketecture",
        "ont-l1-layered-stack",
        "ont-l1b-layer-patterns",
        "ont-l2a-logical-data-model-er",
        "ont-l2b-physical-property-graph",
        "ont-l2c-query-patterns",
        "ont-l2d-scaling-tiers",
    ],
}

DEFAULT_FILES: list[str] = [
    "README.md",
]


@dataclass
class Diagram:
    index: int
    slug: str
    source: str
    indent: str
    span: tuple[int, int]


def slugs_for(md_path: Path) -> list[str]:
    return SLUGS_BY_FILE.get(md_path.name, [])


def extract_diagrams(md_text: str, slug_list: list[str], file_stem: str) -> list[Diagram]:
    diagrams: list[Diagram] = []
    for i, match in enumerate(MERMAID_FENCE_RE.finditer(md_text), start=1):
        indent = match.group(1) or ""
        source = match.group(2)
        if i <= len(slug_list):
            slug = slug_list[i - 1]
        else:
            slug = f"{file_stem.lower()}-diagram-{i:02d}"
        diagrams.append(
            Diagram(
                index=i,
                slug=slug,
                source=source,
                indent=indent,
                span=match.span(),
            )
        )
    return diagrams


def render_png(
    mmd_path: Path,
    png_path: Path,
    theme: str = "default",
    puppeteer_config: Path | None = None,
    width: int = 2400,
    height: int = 2400,
    scale: int = 2,
) -> None:
    cmd = [
        "mmdc",
        "-i",
        str(mmd_path),
        "-o",
        str(png_path),
        "-t",
        theme,
        "-b",
        "white",
        "-w",
        str(width),
        "-H",
        str(height),
        "--scale",
        str(scale),
    ]
    if puppeteer_config is not None:
        cmd.extend(["-p", str(puppeteer_config)])
    print(f"  → rendering {png_path.name} …", flush=True)
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(
            f"\n[mmdc failed for {mmd_path.name}]\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}\n"
        )
        raise SystemExit(result.returncode)


def replace_blocks(
    md_text: str,
    diagrams: list[Diagram],
    rel_dir: str,
    keep_source_comment: bool = False,
) -> str:
    new_text = md_text
    for d in reversed(diagrams):
        start, end = d.span
        img_path = f"{rel_dir}/{d.slug}.png"
        replacement_lines = [
            f"{d.indent}![Diagram {d.index} — {d.slug}]({img_path})",
        ]
        if keep_source_comment:
            replacement_lines.extend(
                [
                    "",
                    f"{d.indent}<!-- mermaid-source: {d.slug}",
                ]
            )
            for line in d.source.splitlines():
                replacement_lines.append(f"{d.indent}{line}")
            replacement_lines.append(f"{d.indent}-->")
        replacement = "\n".join(replacement_lines)
        new_text = new_text[:start] + replacement + new_text[end:]
    return new_text


SOURCE_COMMENT_RE = re.compile(
    r"\n?\n?(?P<indent>[ \t]*)<!-- mermaid-source:[^\n]*\n.*?\n(?P=indent)-->\s*?(?=\n|$)",
    re.DOTALL,
)


def strip_source_comments(md_text: str) -> tuple[str, int]:
    count = 0

    def repl(_match: re.Match[str]) -> str:
        nonlocal count
        count += 1
        return ""

    new_text = SOURCE_COMMENT_RE.sub(repl, md_text)
    return new_text, count


def convert_file(
    md_path: Path,
    diagrams_dir: Path,
    theme: str,
    puppeteer_config: Path | None,
    width: int,
    height: int,
    keep_source_comment: bool = False,
) -> int:
    if not md_path.exists():
        sys.stderr.write(f"ERROR: input markdown not found: {md_path}\n")
        return 0

    md_text = md_path.read_text(encoding="utf-8")
    slug_list = slugs_for(md_path)
    diagrams = extract_diagrams(md_text, slug_list, md_path.stem)
    if not diagrams:
        print(f"  · No Mermaid blocks in {md_path.name}; skipping.")
        return 0

    print(f"\n→ {md_path.name}: found {len(diagrams)} Mermaid block(s).")
    for d in diagrams:
        mmd_path = diagrams_dir / f"{d.slug}.mmd"
        png_path = diagrams_dir / f"{d.slug}.png"
        mmd_path.write_text(d.source + "\n", encoding="utf-8")
        render_png(
            mmd_path,
            png_path,
            theme=theme,
            puppeteer_config=puppeteer_config,
            width=width,
            height=height,
        )

    rel_dir = diagrams_dir.relative_to(md_path.parent).as_posix()
    rewritten = replace_blocks(
        md_text,
        diagrams,
        rel_dir,
        keep_source_comment=keep_source_comment,
    )

    backup_path = md_path.with_suffix(md_path.suffix + ".pre-mermaid-render.bak")
    if not backup_path.exists():
        shutil.copy2(md_path, backup_path)
        print(f"  · Backup written: {backup_path.name}")

    md_path.write_text(rewritten, encoding="utf-8")
    print(f"  · Rewrote {md_path.name} with {len(diagrams)} image reference(s).")
    return len(diagrams)


def strip_source_comments_in_files(md_paths: list[Path]) -> int:
    grand_total = 0
    for md_path in md_paths:
        if not md_path.exists():
            print(f"  · {md_path.name}: not found, skipping.")
            continue
        original = md_path.read_text(encoding="utf-8")
        new_text, count = strip_source_comments(original)
        if count == 0:
            print(f"  · {md_path.name}: no source comments found.")
            continue
        md_path.write_text(new_text, encoding="utf-8")
        print(f"  · {md_path.name}: stripped {count} source comment block(s).")
        grand_total += count
    return grand_total


def render_all_mmd(
    diagrams_dir: Path,
    theme: str,
    puppeteer_config: Path | None,
    width: int,
    height: int,
) -> int:
    mmd_files = sorted(diagrams_dir.glob("*.mmd"))
    if not mmd_files:
        print(f"No .mmd files found in {diagrams_dir}; nothing to render.")
        return 0
    print(f"\n→ Re-rendering {len(mmd_files)} .mmd file(s) in {diagrams_dir.name}/ …")
    for mmd_path in mmd_files:
        png_path = mmd_path.with_suffix(".png")
        render_png(
            mmd_path,
            png_path,
            theme=theme,
            puppeteer_config=puppeteer_config,
            width=width,
            height=height,
        )
    return len(mmd_files)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_md", type=Path, nargs="?", default=None)
    parser.add_argument("--diagrams-dir", type=Path, default=None)
    parser.add_argument("--theme", default="default", choices=["default", "dark", "forest", "neutral"])
    parser.add_argument("--puppeteer-config", type=Path, default=None)
    parser.add_argument("--width", type=int, default=2400)
    parser.add_argument("--height", type=int, default=2400)
    parser.add_argument("--mmd-only", action="store_true")
    parser.add_argument("--keep-source-comment", action="store_true")
    parser.add_argument("--strip-source-comments", action="store_true")
    args = parser.parse_args()

    script_dir = Path(__file__).resolve().parent
    doc_dir = script_dir.parent

    if args.puppeteer_config is None:
        candidate = script_dir / "puppeteer.config.json"
        puppeteer_config = candidate if candidate.exists() else None
    else:
        puppeteer_config = args.puppeteer_config.resolve()

    diagrams_dir: Path = (args.diagrams_dir or (doc_dir / "diagrams")).resolve()
    diagrams_dir.mkdir(parents=True, exist_ok=True)

    if args.input_md is not None:
        targets = [args.input_md.resolve()]
    else:
        targets = [(doc_dir / name).resolve() for name in DEFAULT_FILES]

    if args.strip_source_comments:
        print(f"\n→ Stripping <!-- mermaid-source: ... --> blocks from {len(targets)} file(s) …")
        removed = strip_source_comments_in_files(targets)
        print(f"\nDone. Removed {removed} source comment block(s).")
        return 0

    if args.mmd_only:
        total = render_all_mmd(diagrams_dir, args.theme, puppeteer_config, args.width, args.height)
        print(f"\nDone. Re-rendered {total} .mmd file(s) into {diagrams_dir}")
        return 0

    total = 0
    for md_path in targets:
        total += convert_file(
            md_path,
            diagrams_dir,
            args.theme,
            puppeteer_config,
            args.width,
            args.height,
            keep_source_comment=args.keep_source_comment,
        )

    print(f"\nDone. Rendered {total} diagram(s) into {diagrams_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
