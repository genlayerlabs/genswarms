#!/bin/bash
set -euo pipefail
T=$(mktemp -d); mkdir -p "$T/_site"
# the copy command under test (keep identical to pages.yml):
rsync -a --exclude src --exclude tests --exclude tools --exclude i18n --exclude build.mjs website/ "$T/_site/"
for f in index.html 404.html favicon.svg favicon-32.png apple-touch-icon.png og-image.png robots.txt sitemap.xml llms.txt CNAME; do test -f "$T/_site/$f" || { echo "missing $f"; exit 1; }; done
# every built language version ships (website/<dir>/index.html, from website/i18n/<dir>.json)
for f in website/*/index.html; do
  [ -e "$f" ] || continue; d=${f#website/}; l=${d%/index.html}
  for g in "$d" "og-$l.png"; do test -f "$T/_site/$g" || { echo "missing $g"; exit 1; }; done
done
for d in src tests tools i18n build.mjs; do test ! -e "$T/_site/$d" || { echo "leaked $d"; exit 1; }; done
echo "deploy copy ok"
