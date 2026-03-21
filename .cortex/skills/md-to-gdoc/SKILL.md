---
name: md-to-gdoc
description: "Convert markdown files with Mermaid diagrams to Google Docs-compatible DOCX. Renders Mermaid code blocks to PNG images and assembles a Word document via pandoc. Use when: convert markdown, export to google docs, mermaid to docx, md to word, export docx, share without git, markdown to word, render mermaid diagrams."
---

# Markdown to Google Docs Converter

Converts markdown files containing Mermaid diagrams into DOCX files suitable for Google Docs import. Mermaid code blocks are rendered to PNG images and embedded in the output document.

## Prerequisites

- **pandoc** (required) -- converts markdown to DOCX
- **Python 3.8+** (required) -- runs the conversion script
- **mmdc** (optional) -- mermaid-cli for offline rendering. If not installed, the script uses the kroki.io public API.

Install missing dependencies:
```bash
# pandoc (macOS)
brew install pandoc

# mermaid-cli (optional, for offline rendering)
npm install -g @mermaid-js/mermaid-cli
```

## Workflow

### Step 1: Identify Input File

**⚠️ MANDATORY STOPPING POINT** -- Ask the user which markdown file to convert:

```
Which markdown file should I convert to DOCX?
```

If the user already specified a file, skip this step.

### Step 2: Check Dependencies

Run the conversion script with `--check` to verify prerequisites:

```bash
python3 <SKILL_DIR>/scripts/md_to_docx.py --check
```

If pandoc is missing, inform the user and stop. If mmdc is missing, note that the kroki.io API will be used (requires internet).

### Step 3: Run Conversion

Execute the script:

```bash
python3 <SKILL_DIR>/scripts/md_to_docx.py \
  --input <path/to/file.md> \
  --output <path/to/file.docx>
```

**Options:**
| Flag | Default | Description |
|------|---------|-------------|
| `--input` | (required) | Path to input markdown file |
| `--output` | `<input_stem>.docx` | Path to output DOCX file |
| `--bg-color` | `white` | Background color for Mermaid diagrams |
| `--theme` | `default` | Mermaid theme: default, dark, forest, neutral |
| `--use-api` | auto | Force kroki.io API even if mmdc is installed |
| `--keep-images` | false | Keep rendered PNG files after conversion |
| `--image-dir` | temp dir | Directory for rendered diagram images |

### Step 4: Report Results

Present the output:

```
Conversion complete:
  Input:    <input_file>
  Output:   <output_file>
  Diagrams: <N> Mermaid diagrams rendered to PNG
  Method:   mmdc (local) | kroki.io API

Import to Google Docs:
  1. Open Google Docs
  2. File > Open > Upload tab
  3. Select the .docx file
```

## Stopping Points

| Point | Condition | Action |
|-------|-----------|--------|
| Step 1 | No file specified | Ask user for input file |
| Step 2 | pandoc missing | Tell user to install pandoc |
| Step 3 | Script errors | Report error, suggest fixes |

## Files

```
md-to-gdoc/
├── SKILL.md                    # This file
└── scripts/
    └── md_to_docx.py          # Standalone converter script
```

## Output

1. **DOCX file** with Mermaid diagrams rendered as embedded PNG images
2. **Console summary** with diagram count and rendering method used

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| pandoc not found | Not installed | `brew install pandoc` |
| Diagram render fails (API) | No internet or kroki.io down | Install mmdc for offline: `npm install -g @mermaid-js/mermaid-cli` |
| Diagram render fails (mmdc) | Node/Chromium issue | Use `--use-api` flag to fall back to kroki.io |
| DOCX images missing | pandoc resource path | Ensure `--image-dir` is accessible |
| Large diagrams truncated | API timeout or size limit | Install mmdc for local rendering: `npm install -g @mermaid-js/mermaid-cli` |
