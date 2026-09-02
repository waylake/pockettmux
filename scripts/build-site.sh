#!/usr/bin/env bash
# Assemble the landing page into _site/ — the same three lines CI runs.
#
# docs/assets/ is the single source of truth for screenshots (the README uses
# the same files); the page references them as assets/*.png, so they are copied
# in rather than duplicated in the repo.
set -euo pipefail
cd "$(dirname "$0")/.."

rm -rf _site
mkdir -p _site
cp -R site/. _site/
cp -R docs/assets _site/assets

echo "_site assembled: $(find _site -type f | wc -l | tr -d ' ') files, $(du -sh _site | cut -f1)"

if [ "${1:-}" = "--serve" ]; then
  port="${2:-4321}"
  echo "http://localhost:${port}/"
  exec python3 -m http.server "$port" --directory _site
fi
