#!/usr/bin/env bash
# Check a freshly rendered course page in docs/ before committing it.
#
# Usage: check-rendered-page.sh <dir/page> [base-ref]
#   <dir/page>  source path with or without .qmd, e.g. understand/predation-growth-and-mortality
#   [base-ref]  git ref holding the previously published page (default: HEAD)
#
# Run from the root of the checkout that was rendered. Exits 1 if it found
# something to look at, 0 otherwise.
set -uo pipefail

page=${1:?usage: check-rendered-page.sh <dir/page> [base-ref]}
page=${page%.qmd}
base=${2:-HEAD}
html="docs/$page.html"
[ -f "$html" ] || { echo "No $html here: run from the project root after rendering." >&2; exit 2; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
found=0

# R output lands in the page as e.g. "Warning: Removed 181 rows ..." or
# "Warning in f(x): ...". Prose like "gives a warning" has no colon and is skipped.
diag='(Warning|Error)( message| in [^:<]*)?:[^<]{0,200}'

echo "== R warnings and errors not in $base"
grep -o -E "$diag" "$html" | sort -u > "$tmp/new"
if git show "$base:$html" > "$tmp/old.html" 2>/dev/null; then
  grep -o -E "$diag" "$tmp/old.html" | sort -u > "$tmp/old"
else
  echo "  (page is not in $base, so every warning counts as new)"
  : > "$tmp/old"
fi
comm -13 "$tmp/old" "$tmp/new" > "$tmp/added"
if [ -s "$tmp/added" ]; then sed 's/^/  /' "$tmp/added"; found=1; else echo "  none"; fi
echo "  ($(wc -l < "$tmp/new") distinct in page, $(wc -l < "$tmp/old") in $base)"

echo "== Figure files the page does not reference"
figdir="docs/${page}_files/figure-html"
n=0
if [ -d "$figdir" ]; then
  for f in "$figdir"/*; do
    [ -e "$f" ] || continue
    if ! grep -qF "$(basename "$f")" "$html"; then echo "  $f"; n=$((n + 1)); fi
  done
fi
if [ "$n" -gt 0 ]; then found=1; else echo "  none"; fi

echo "== Relative links and anchors that do not resolve"
here=$(dirname "$html")
n=0
while read -r href; do
  case "$href" in
    ""|"#"|http:*|https:*|mailto:*|//*|javascript:*|data:*) continue ;;
  esac
  path=${href%%#*}
  path=${path%%\?*}
  anchor=""
  [[ "$href" == *"#"* ]] && anchor=${href#*#}
  if [ -z "$path" ]; then
    target=$html
  else
    target=$(realpath -m --relative-to=. "$here/$path")
    [ -d "$target" ] && target="$target/index.html"
  fi
  if [ ! -e "$target" ]; then
    echo "  $href  (no file $target)"; n=$((n + 1))
  elif [ -n "$anchor" ] && [[ "$target" == *.html ]] && ! grep -qF "id=\"$anchor\"" "$target"; then
    echo "  $href  (no id=\"$anchor\" in $target)"; n=$((n + 1))
  fi
done < <(grep -o -E 'href="[^"]*"' "$html" | sed -E 's/^href="(.*)"$/\1/' | sort -u)
if [ "$n" -gt 0 ]; then found=1; else echo "  none"; fi

echo "== Tracked files outside docs/ that are modified"
git status --short --untracked-files=no -- . ':!docs' > "$tmp/outside"
if [ -s "$tmp/outside" ]; then
  sed 's/^/  /' "$tmp/outside"
  echo "  (changed by the render, or already dirty before it: commit only intended changes)"
  found=1
else
  echo "  none"
fi

exit $found
