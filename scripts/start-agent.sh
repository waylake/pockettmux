#!/bin/bash
# start-agent.sh — build (if needed) and run the PocketTmux agent (pockettmuxd).
# Token lives in ~/.pockettmux/token (created on first run; paste it into the
# phone once). Logs to ~/.pockettmux/agent.log. Stop with: pkill pockettmuxd
set -euo pipefail
cd "$(dirname "$0")/../App"

BIN=$(find ~/Library/Developer/Xcode/DerivedData -path "*PocketTmux*/Build/Products/Debug/pockettmuxd" 2>/dev/null | head -1 || true)
if [ -z "${BIN:-}" ] || [ ! -x "$BIN" ]; then
    echo "→ building agent…"
    xcodegen generate >/dev/null
    xcodebuild -project PocketTmux.xcodeproj -scheme PocketTmuxAgent -configuration Debug build >/dev/null
    BIN=$(find ~/Library/Developer/Xcode/DerivedData -path "*PocketTmux*/Build/Products/Debug/pockettmuxd" | head -1)
fi

mkdir -p ~/.pockettmux
if pgrep -x pockettmuxd >/dev/null; then
    echo "pockettmuxd already running — token: $(sed 's/\(....\).*/\1…/' ~/.pockettmux/token 2>/dev/null || echo '?')"
else
    nohup "$BIN" > ~/.pockettmux/agent.log 2>&1 &
    echo "pockettmuxd started (pid $!) — ws://0.0.0.0:7682"
    echo "token: $(cat ~/.pockettmux/token)"
fi