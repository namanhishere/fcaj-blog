# FCAJ Internship Report

Bilingual (EN/VI) Hugo site for an AWS internship report, deployed to GitHub Pages. Also generates PDF reports automatically from Hugo content on every push to `main`.

## Quick Start

### Hugo Site (Local)

```bash
# Clone with submodules
git clone --recurse-submodules <repo-url>
cd fcaj-blog

# Run Hugo dev server
hugo server -D

# Build for production
hugo --minify
```

Requires **Hugo 0.134.3** (extended).

### PDF Reports (Local)

```bash
# Install dependencies (Ubuntu/Debian)
sudo apt-get install -y pandoc texlive-latex-recommended texlive-latex-extra \
  texlive-fonts-recommended texlive-lang-other latexmk

# Convert Hugo content to LaTeX
python3 scripts/convert_hugo_to_latex.py

# Compile Vietnamese PDF (3 passes)
cd report
latexmk -pdf -interaction=nonstopmode main.tex
latexmk -pdf -interaction=nonstopmode main.tex
latexmk -pdf -interaction=nonstopmode main.tex
cp main.pdf ../report_vn.pdf

# Compile English PDF (3 passes)
latexmk -pdf -interaction=nonstopmode main_en.tex
latexmk -pdf -interaction=nonstopmode main_en.tex
latexmk -pdf -interaction=nonstopmode main_en.tex
cp main_en.pdf ../report_en.pdf
```

On **macOS**:
```bash
brew install pandoc
brew install --cask mactex
# Then same commands as above
```

### Adding D2 and D3 form

To include the D2 and D3 form. Please add ``formD2.pdf`` and ``formD3.pdf`` in to ``/report/form/...``

## Project Structure

```
fcaj-blog/
├── config.toml              # Hugo config (bilingual EN/VI)
├── content/                 # Hugo content (markdown)
│   ├── _index.md            # Homepage (EN)
│   ├── _index.vi.md         # Homepage (VI)
│   ├── 1-Worklog/           # 12 weeks of worklogs
│   ├── 2-Proposal/          # IoT Weather Platform proposal
│   ├── 3-BlogsPosted/       # Blog posts
│   ├── 4-EventParticipated/ # Events attended
│   ├── 5-Workshop/          # S3 VPC Endpoints workshop
│   ├── 6-Self-evaluation/   # Self-assessment
│   └── 7-Feedback/          # Feedback & sharing
├── report/                  # LaTeX PDF report
│   ├── main.tex             # Vietnamese report template
│   ├── main_en.tex          # English report template
│   ├── form/
│   │   ├── formD2.pdf       # Internship program form (D2)
│   │   └── formD3.pdf       # Admission results form (D3)
│   ├── generated/           # Auto-generated .tex from Hugo content
│   └── Images/hcmut.png     # University logo
├── scripts/
│   ├── convert_hugo_to_latex.py  # Hugo → LaTeX converter
│   └── hugo-notice.lua      # Pandoc filter for notice boxes
├── static/                  # Static assets (images, CSS, fonts)
├── layouts/                 # Custom Hugo layout overrides
└── .github/workflows/hugo.yml  # CI: deploy + PDF build + release
```

## How the PDF Pipeline Works

```
Hugo .md files                  LaTeX .tex files              PDF
──────────────────────────────────────────────────────────────────
content/1-Worklog/              report/generated/vi/          report_vn.pdf
  1.1-Week1/_index.vi.md  ─┐     1_1_Week1.tex
  1.2-Week2/_index.vi.md   │     1_2_Week2.tex
  ...                       ├──►  ...                    ──►  report_en.pdf
  7-Feedback/_index.vi.md  ─┘     7_Feedback.tex
                           │
                           │   report/generated/en/
content/1-Worklog/         │     1_1_Week1.tex
  1.1-Week1/_index.md   ───┘     1_2_Week2.tex
  ...                            ...
```

1. `convert_hugo_to_latex.py` dynamically walks `content/`, discovers all `_index.md` / `_index.vi.md` pages, strips frontmatter, converts shortcodes (`{{% notice warning %}}` → `\begin{mdframed}...`), normalizes image paths (resolved via `\graphicspath`), and pipes through **pandoc** for markdown→LaTeX conversion.
2. A master include file (`content_body_en.tex` / `content_body_vi.tex`) is generated, grouping pages by section with proper `\subsection` headers.
3. `main.tex` / `main_en.tex` include the generated files, plus embedded D2/D3 form PDFs (no header/footer on form pages).

## CI/CD

On every push to `main`:

| Job | What it does |
|-----|-------------|
| `build-deploy` | Builds Hugo site → deploys to `gh-pages` branch |
| `build-pdf` | Converts Hugo content → compiles VN + EN PDFs → creates/updates GitHub Release (`latest` tag) |

Each release contains `report_vn.pdf` and `report_en.pdf`.

## Adding New Content

1. Create `_index.md` / `_index.vi.md` files in `content/` following the directory naming convention (e.g. `8-NewSection/_index.md`)
2. Add section titles to `SECTION_TITLES_EN` / `SECTION_TITLES_VI` in `scripts/convert_hugo_to_latex.py`
3. The script discovers pages dynamically — no other changes needed


## Report-Specific Frontmatter Options

The PDF generator supports several optional frontmatter fields that control how Hugo pages are included in the generated LaTeX/PDF reports.

### Excluding a Page from the PDF Report

To prevent a page (and all of its descendants) from appearing in the generated report:

```yaml
---
title: "Internal Notes"
includeInReport: false
---
```

Supported aliases:

```yaml
includeInReport: false
include_in_report: false
isincludeinlatex: false
includeInLatex: false
```

When a section container is excluded, all child pages are excluded automatically.

---

### Selecting Specific Columns from Markdown Tables

Large markdown tables often do not render well in PDF format.

You can choose which columns should be included:

```yaml
---
title: "Week 1 Worklog"

reportTableColumns:
  - Day
  - Task
  - Completion Date
---
```

Vietnamese example:

```yaml
---
title: "Tuần 1"

reportTableColumns:
  - Thứ
  - Công việc
  - Ngày hoàn thành
---
```

Only the listed columns will be preserved in the generated PDF.

---

### Selecting Specific Headings

If a page contains many sections but only some should appear in the PDF report:

```yaml
---
title: "Week 1"

reportHeadings:
  - Week 1 Objectives
  - Tasks to be carried out this week
  - Week 1 Achievements
---
```

Only the selected headings and their content will be included.

Supported aliases:

```yaml
reportHeadings
report_headings
latexHeadings
latex_headings
```

---

### Worklog Tables

Worklog pages can be rendered using a custom LaTeX table generator instead of Pandoc's default table conversion.

```yaml
---
title: "Week 1 Worklog"

reportType: worklog

reportTableColumns:
  - Day
  - Task
  - Completion Date
---
```

Supported aliases:

```yaml
reportType
report_type
```

When `reportType: worklog` is enabled:

* The first markdown table on the page is converted into a custom LaTeX `longtable`.
* Task cells are rendered as multi-line lists.
* Selected columns are preserved using `reportTableColumns`.
* The output is optimized for PDF readability compared to Pandoc's default table rendering.

---

### Example

```yaml
---
title: "Week 1 Worklog"

includeInReport: true

reportType: worklog

reportTableColumns:
  - Day
  - Task
  - Completion Date

reportHeadings:
  - Week 1 Objectives
  - Tasks to be carried out this week
  - Week 1 Achievements
---
```

This configuration:

* Includes the page in the PDF report.
* Uses the custom worklog table renderer.
* Keeps only the selected table columns.
* Includes only the selected headings.


## License

Template content provided as reference — do not copy verbatim for your own report.
