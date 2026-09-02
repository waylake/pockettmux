#!/bin/bash
# stop-agent.sh — stop the headless PocketTmux agent started by start-agent.sh.
#
#   scripts/stop-agent.sh          # every pockettmuxd process
#   scripts/stop-agent.sh 7701     # only the one listening on that port
set -euo pipefail

PORT=${1:-${POCKETTMUX_PORT:-}}

if [ -n "$PORT" ]; then
    PIDS=$(lsof -ti "tcp:$PORT" -sTCP:LISTEN 2>/dev/null || true)
    if [ -z "$PIDS" ]; then
        echo "nothing is listening on port $PORT"
        exit 0
    fi
    for PID in $PIDS; do
        NAME=$(ps -o comm= -p "$PID" 2>/dev/null || true)
        case "$NAME" in
            */pockettmuxd|pockettmuxd)
                kill "$PID" && echo "stopped pockettmuxd (pid $PID, port $PORT)" ;;
            *)
                echo "pid $PID on port $PORT is '$NAME', not pockettmuxd — leaving it alone" ;;
        esac
    done
    exit 0
fi

if pkill -x pockettmuxd; then
    echo "stopped pockettmuxd"
else
    echo "pockettmuxd is not running"
fi
