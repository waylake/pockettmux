#!/bin/bash
# pair.sh — show the pairing QR on screen so the phone can scan & connect.
# Also prints the deep link as a fallback (open it on the phone, or paste the
# host/port/token into Add Mac → Enter manually). Requires a running agent
# (scripts/start-agent.sh or the Mac app) and the phone on the same
# Tailscale network / LAN.
#
# The Mac menu-bar app's "Pair iPhone…" window is the GUI equivalent of this.
#
#   scripts/pair.sh                      # port 7682
#   POCKETTMUX_PORT=7701 scripts/pair.sh
set -euo pipefail
cd "$(dirname "$0")/.."

TOKEN_FILE=~/.pockettmux/token
[ -f "$TOKEN_FILE" ] || { echo "no token yet — run scripts/start-agent.sh first"; exit 1; }
TOKEN=$(tr -d '\n' < "$TOKEN_FILE")
PORT=${POCKETTMUX_PORT:-7682}
NAME=$(scutil --get ComputerName 2>/dev/null || hostname -s)

# Preferred: Tailscale IP (phone reaches it anywhere); fallback: LAN IP.
HOST=$(tailscale ip -4 2>/dev/null | head -1 | tr -d ' ' || true)
if [ -z "${HOST:-}" ]; then
    HOST=$(ipconfig getifaddr en0 2>/dev/null || true)
fi
[ -n "${HOST:-}" ] || { echo "could not determine this Mac's address"; exit 1; }

# Percent-encode the name for the URL query (spaces, quotes, non-ASCII…).
# Byte-wise (LC_ALL=C); the & 255 mask matters on bash 3.2, whose printf
# sign-extends bytes ≥ 0x80.
urlencode() {
    local LC_ALL=C s=$1 out='' c i
    for (( i = 0; i < ${#s}; i++ )); do
        c=${s:i:1}
        case "$c" in
            [a-zA-Z0-9.~_-]) out+=$c ;;
            *) out+=$(printf '%%%02X' "$(( $(printf '%d' "'$c") & 255 ))") ;;
        esac
    done
    printf '%s' "$out"
}

PAYLOAD="pockettmux://pair?host=$HOST&port=$PORT&token=$TOKEN&name=$(urlencode "$NAME")"
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
echo "  name  $NAME"
echo "  host  $HOST"
echo "  port  $PORT"
echo "  token $(printf '%s' "$TOKEN" | sed 's/\(....\).*/\1…/')"
echo "  QR    $OUT"
echo "  link  $PAYLOAD"
echo "On the iPhone: PocketTmux → Add Mac → Scan QR (or open the link)."
open "$OUT"
