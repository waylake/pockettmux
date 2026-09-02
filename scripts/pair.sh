#!/bin/bash
# pair.sh — show the pairing QR on screen so the phone can scan & connect.
# Also prints the deep link as a fallback. Requires the agent to be running
# (scripts/start-agent.sh) and the phone on the same Tailscale/LAN.
set -euo pipefail
cd "$(dirname "$0")/.."

TOKEN_FILE=~/.pockettmux/token
[ -f "$TOKEN_FILE" ] || { echo "no token yet — run scripts/start-agent.sh first"; exit 1; }
TOKEN=$(tr -d '\n' < "$TOKEN_FILE")
PORT=${POCKETTMUX_PORT:-7682}

# Preferred: Tailscale IP (phone reaches it anywhere); fallback: LAN IP.
HOST=$(tailscale ip -4 2>/dev/null | head -1 | tr -d ' ' || true)
if [ -z "${HOST:-}" ]; then
    HOST=$(ipconfig getifaddr en0 2>/dev/null || true)
fi
[ -n "${HOST:-}" ] || { echo "could not determine this Mac's address"; exit 1; }

PAYLOAD="pockettmux://pair?host=$HOST&port=$PORT&token=$TOKEN"
OUT=~/.pockettmux/pair-qr.png
mkdir -p ~/.pockettmux

# Compile the tiny QR generator once.
QRBIN=~/.pockettmux/qrgen
if [ ! -x "$QRBIN" ]; then
    echo "→ building qrgen…"
    swiftc -O "$PWD/scripts/qrgen.swift" -o "$QRBIN"
fi

"$QRBIN" "$PAYLOAD" "$OUT"
echo "pairing info:"
echo "  host  $HOST"
echo "  port  $PORT"
echo "  token $(printf '%s' "$TOKEN" | sed 's/\(....\).*/\1…/')"
echo "  QR    $OUT"
open "$OUT"