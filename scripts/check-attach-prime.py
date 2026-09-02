#!/usr/bin/env python3
"""End-to-end check: attach the agent to a tmux session running a full-screen TUI
and assert the FIRST screen frame primes the emulator (alt screen + content)."""
import socket, base64, os, json, struct, sys, time, subprocess, hashlib, secrets

HOST, PORT = "127.0.0.1", 7682
TOKEN = open(os.path.expanduser("~/.pockettmux/token")).read().strip()

def ws_connect():
    s = socket.create_connection((HOST, PORT), timeout=5)
    key = base64.b64encode(secrets.token_bytes(16)).decode()
    s.sendall((f"GET / HTTP/1.1\r\nHost: {HOST}:{PORT}\r\nUpgrade: websocket\r\n"
               f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\n"
               "Sec-WebSocket-Version: 13\r\n\r\n").encode())
    buf = b""
    while b"\r\n\r\n" not in buf:
        buf += s.recv(4096)
    assert b"101" in buf.split(b"\r\n")[0], buf[:200]
    return s, buf.split(b"\r\n\r\n", 1)[1]

def send(s, obj):
    p = json.dumps(obj).encode()
    hdr = b"\x81"
    n = len(p)
    hdr += bytes([0x80 | (n if n < 126 else 126 if n < 65536 else 127)])
    if 126 <= n < 65536: hdr += struct.pack(">H", n)
    elif n >= 65536:     hdr += struct.pack(">Q", n)
    m = secrets.token_bytes(4)
    s.sendall(hdr + m + bytes(b ^ m[i % 4] for i, b in enumerate(p)))

def frames(s, rest, deadline):
    buf = rest
    while time.time() < deadline:
        while True:
            if len(buf) < 2: break
            b1, b2 = buf[0], buf[1]
            n = b2 & 0x7F; off = 2
            if n == 126: n = struct.unpack(">H", buf[2:4])[0]; off = 4
            elif n == 127: n = struct.unpack(">Q", buf[2:10])[0]; off = 10
            if len(buf) < off + n: break
            payload, buf = buf[off:off+n], buf[off+n:]
            if b1 & 0x0F in (1, 2):
                yield json.loads(payload)
        s.settimeout(max(0.05, deadline - time.time()))
        try: buf += s.recv(65536)
        except (socket.timeout, OSError): return

def run(name, setup_cmd, expect_alt, minsize=200):
    subprocess.run(["tmux", "kill-session", "-t", name], capture_output=True)
    subprocess.run(["tmux", "new-session", "-d", "-s", name, "-x", "80", "-y", "24", setup_cmd], check=True)
    time.sleep(1.5)
    s, rest = ws_connect()
    send(s, {"type": "hello", "payload": {"auth": TOKEN, "v": 1}})
    send(s, {"type": "session.attach", "payload": {"id": name}})
    first = None
    for msg in frames(s, rest, time.time() + 4):
        if msg.get("type") == "screen" and first is None:
            first = base64.b64decode(msg["payload"]["data"])
            break
    s.close()
    subprocess.run(["tmux", "kill-session", "-t", name], capture_output=True)
    assert first is not None, f"{name}: no screen frame at all"
    alt = b"\x1b[?1049h" in first
    assert alt == expect_alt, f"{name}: alt-screen primed={alt}, expected {expect_alt}\n{first[:120]!r}"
    assert len(first) > minsize, f"{name}: frame too small ({len(first)}B) — pane content missing"
    print(f"ok  {name}: {len(first)}B first frame, alt={alt}")
    return first

f = run("pt_alt", "vim /tmp/pt_big.txt", True)
assert b"1" in f, "vim content missing"
g = run("pt_norm", "bash -c 'seq 1 300; sleep 30'", False)
assert b"300" in g, f"shell scrollback missing: {g[-200:]!r}"
assert g.count(b"\r\n") > 100, f"scrollback not captured ({g.count(chr(13).encode())} lines)"
print("ok  scrollback captured:", g.count(b"\r\n"), "lines")

m = run("pt_mouse", "bash -c \"printf '\\033[?1049h\\033[?1000h\\033[?1002h\\033[?1006hMOUSE-ON'; cat\"", True, minsize=40)
assert b"\x1b[?1000h" in m and b"\x1b[?1006h" in m, f"mouse mode not primed: {m[:160]!r}"
print("ok  mouse reporting primed")
