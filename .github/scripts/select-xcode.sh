#!/usr/bin/env bash
# Select the Xcode the project is built with (baseline 26.2, see CLAUDE.md).
#
# macos-26 runners ship several Xcode 26.x versions and default to the newest.
# Pin the documented baseline when it is present, otherwise take the highest
# Xcode 26 on the image; anything older cannot compile the app (isolated
# `@MainActor` conformances, Sendable CIContext).
set -euo pipefail

baseline="${XCODE_BASELINE:-26.2}"
app="/Applications/Xcode_${baseline}.app"

if [ ! -d "$app" ]; then
  app=$(ls -d /Applications/Xcode_26*.app 2>/dev/null | sort -V | tail -1 || true)
fi

if [ -z "${app}" ] || [ ! -d "$app" ]; then
  echo "select-xcode: no Xcode 26 on this runner. Available:" >&2
  ls -d /Applications/Xcode*.app >&2 || true
  exit 1
fi

sudo xcode-select -s "$app"
echo "select-xcode: using $app"
xcodebuild -version
