#!/bin/bash
# start-agent.sh — build (if needed) and run the headless PocketTmux agent
# (pockettmuxd) in the background.
#
#   scripts/start-agent.sh                  # ws://0.0.0.0:7682/ws
#   POCKETTMUX_PORT=7701 scripts/start-agent.sh
#
# The token lives in ~/.pockettmux/token (created on first run; shared with the
# Mac app and scripts/pair.sh). Output goes to ~/.pockettmux/agent.log.
# Stop with: scripts/stop-agent.sh [port]
# The Mac menu-bar app (scheme PocketTmuxMac) is the GUI equivalent of this.
set -euo pipefail
cd "$(dirname "$0")/../App"

PORT=${POCKETTMUX_PORT:-7682}
BIN=$PWD/build/Daemon/Build/Products/Debug/pockettmuxd

if [ ! -x "$BIN" ]; then
    echo "→ building pockettmuxd…"
    [ -d PocketTmux.xcodeproj ] || xcodegen generate >/dev/null
    xcodebuild build \
        -project PocketTmux.xcodeproj \
        -scheme pockettmuxd \
        -configuration Debug \
        -destination "platform=macOS,arch=$(uname -m)" \
        -derivedDataPath build/Daemon \
        -skipPackagePluginValidation \
        -quiet
    [ -x "$BIN" ] || { echo "build finished but $BIN is missing"; exit 1; }
fi

mkdir -p ~/.pockettmux
LOG=~/.pockettmux/agent.log

if PID=$(lsof -ti "tcp:$PORT" -sTCP:LISTEN 2>/dev/null | head -1) && [ -n "$PID" ]; then
    echo "port $PORT is already in use (pid $PID: $(ps -o comm= -p "$PID" 2>/dev/null || echo '?'))"
    echo "token: $(cat ~/.pockettmux/token 2>/dev/null || echo '?')"
    exit 0
fi

nohup "$BIN" --port "$PORT" >> "$LOG" 2>&1 &
PID=$!
sleep 1
if ! kill -0 "$PID" 2>/dev/null; then
    echo "pockettmuxd exited immediately — last log lines:"
    tail -n 5 "$LOG"
    exit 1
fi

echo "pockettmuxd started (pid $PID) — ws://0.0.0.0:$PORT/ws"
echo "token: $(cat ~/.pockettmux/token)"
echo "log:   $LOG"
echo "hint:  $BIN --help   (port, name, tmux path, --regenerate-token)"
echo "pair:  scripts/pair.sh   (QR + link; or use the Mac app's Pair iPhone… window)"
