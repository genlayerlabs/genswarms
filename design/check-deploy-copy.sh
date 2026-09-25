#!/bin/bash
set -euo pipefail
T=$(mktemp -d); mkdir -p "$T/_site"
# the copy command under test (keep identical to pages.yml):
rsync -a --exclude src --exclude tests --exclude tools --exclude build.mjs website/ "$T/_site/"
for f in index.html 404.html favicon.svg favicon-32.png apple-touch-icon.png og-image.png robots.txt sitemap.xml llms.txt CNAME; do test -f "$T/_site/$f" || { echo "missing $f"; exit 1; }; done
for d in src tests tools build.mjs; do test ! -e "$T/_site/$d" || { echo "leaked $d"; exit 1; }; done
echo "deploy copy ok"
