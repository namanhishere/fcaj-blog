#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

step()  { printf "${BOLD}==> %s${NC}\n" "$*"; }
ok()    { printf "  ${GREEN}✓${NC} %s\n" "$*"; }
warn()  { printf "  ${YELLOW}!${NC} %s\n" "$*"; }
err()   { printf "  ${RED}✗${NC} %s\n" "$*" >&2; }

usage() {
  cat <<EOF
Usage: ./build.sh [FLAGS]

  --skip-previews     Skip link preview rendering (Docker)
  --skip-diagrams     Skip PlantUML diagram compilation (Docker)
  --skip-pdf          Skip PDF compilation (requires latexmk)
  --skip-hugo         Skip Hugo site build
  --help              Show this message
EOF
  exit 0
}

SKIP_PREVIEWS=false
SKIP_DIAGRAMS=false
SKIP_PDF=false
SKIP_HUGO=false

for arg in "$@"; do
  case "$arg" in
    --skip-previews)  SKIP_PREVIEWS=true ;;
    --skip-diagrams)  SKIP_DIAGRAMS=true ;;
    --skip-pdf)       SKIP_PDF=true ;;
    --skip-hugo)      SKIP_HUGO=true ;;
    --help)           usage ;;
    *) echo "Unknown flag: $arg"; usage ;;
  esac
done

# ── check prerequisites ──────────────────────────────────────────

check_bin() {
  local name="$1" hint="${2:-}"
  if command -v "$name" &>/dev/null; then
    ok "$name"
    return 0
  else
    err "$name not found. ${hint}"
    return 1
  fi
}

echo ""
step "Checking prerequisites"
FAILED=0

if ! $SKIP_HUGO; then
  if ! command -v hugo &>/dev/null; then
    err "hugo not found. Install: https://gohugo.io/installation/"
    FAILED=1
  else
    ok "hugo ($(hugo version | awk '{print $2}' | tr -d 'v'))"
  fi
fi

if ! $SKIP_PDF; then
  check_bin python3     "apt install python3"              || FAILED=1
  check_bin pandoc      "apt install pandoc"               || FAILED=1
  check_bin latexmk     "apt install latexmk"              || FAILED=1
  python3 -c "import yaml" 2>/dev/null \
    && ok "pyyaml" \
    || { err "pyyaml not found. pip install pyyaml"; FAILED=1; }
fi

if ! $SKIP_PREVIEWS || ! $SKIP_DIAGRAMS; then
  check_bin docker      "apt install docker.io"            || FAILED=1
fi

if [ "$FAILED" -ne 0 ]; then
  echo ""
  err "Missing prerequisites — install them and re-run."
  exit 1
fi
echo ""

# ── hugo build ───────────────────────────────────────────────────

if ! $SKIP_HUGO; then
  step "Building Hugo site"
  hugo --minify
  ok "Hugo site built in public/"
fi

# ── diagrams ─────────────────────────────────────────────────────

if ! $SKIP_DIAGRAMS; then
  step "Compiling PlantUML diagrams"
  ./graph/compile.sh
  ok "Diagrams compiled to graph/output/"
  ok "Copied to static/images/diagrams/"
fi

# ── link previews ────────────────────────────────────────────────

if ! $SKIP_PREVIEWS; then
  if [ ! -d "public" ]; then
    warn "public/ does not exist — run Hugo first. Skipping."
  else
    step "Rendering link previews"
    ./scripts/render_link_previews.sh public
    ok "Link previews rendered"
  fi
fi

# ── convert to latex ─────────────────────────────────────────────

if ! $SKIP_PDF; then
  step "Converting Hugo content to LaTeX"
  python3 scripts/convert_hugo_to_latex.py
  ok "LaTeX sources generated in report/generated/"
fi

# ── compile pdfs ─────────────────────────────────────────────────

if ! $SKIP_PDF; then
  step "Compiling Vietnamese PDF (3 passes)"
  (
    cd report
    latexmk -pdf -interaction=nonstopmode main.tex
    latexmk -pdf -interaction=nonstopmode main.tex
    latexmk -pdf -interaction=nonstopmode main.tex
  )
  cp report/main.pdf report_vn.pdf
  ok "report_vn.pdf ready"

  step "Compiling English PDF (3 passes)"
  (
    cd report
    latexmk -pdf -interaction=nonstopmode main_en.tex
    latexmk -pdf -interaction=nonstopmode main_en.tex
    latexmk -pdf -interaction=nonstopmode main_en.tex
  )
  cp report/main_en.pdf report_en.pdf
  ok "report_en.pdf ready"
fi

# ── done ─────────────────────────────────────────────────────────

echo ""
printf "${GREEN}${BOLD}Build complete.${NC}\n"
echo ""
if ! $SKIP_HUGO;  then echo "  Site:          public/"; fi
if ! $SKIP_PDF;   then echo "  VN PDF:        report_vn.pdf"; fi
if ! $SKIP_PDF;   then echo "  EN PDF:        report_en.pdf"; fi
echo ""
