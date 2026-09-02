#!/usr/bin/env python3
"""End-to-end check against a running agent (Mac app or pockettmuxd), over the
real WebSocket, speaking protocol v2. Asserts that:

  1. the FIRST screen frame after attach primes the emulator (alt screen /
     mouse reporting escapes + the pane's content, incl. shell scrollback)
  2. attach carries the phone's size: the pane is resized *before* the paint
  3. windows: list / create / select (→ reset frame) / rename / kill
  4. input round-trips (a marker typed on the "phone" shows up in output)
  5. paste lands as one write, ping answers pong

Env: POCKETTMUX_HOST (127.0.0.1) POCKETTMUX_PORT (7682) POCKETTMUX_TOKEN (~/.pockettmux/token)
"""
import base64, json, os, secrets, socket, struct, subprocess, sys, time

HOST = os.environ.get("POCKETTMUX_HOST", "127.0.0.1")
PORT = int(os.environ.get("POCKETTMUX_PORT", "7682"))
TOKEN = os.environ.get("POCKETTMUX_TOKEN") or open(os.path.expanduser("~/.pockettmux/token")).read().strip()
TMUX = os.environ.get("TMUX_BIN", "tmux")
CLIENT = {"name": "e2e", "model": "python", "app": "check-attach-prime"}


def ws_connect():
    s = socket.create_connection((HOST, PORT), timeout=5)
    key = base64.b64encode(secrets.token_bytes(16)).decode()
    s.sendall((f"GET /ws HTTP/1.1\r\nHost: {HOST}:{PORT}\r\nUpgrade: websocket\r\n"
               f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\n"
               "Sec-WebSocket-Version: 13\r\n\r\n").encode())
    buf = b""
    while b"\r\n\r\n" not in buf:
        buf += s.recv(4096)
    assert b"101" in buf.split(b"\r\n")[0], buf[:200]
    return s, buf.split(b"\r\n\r\n", 1)[1]


def send(s, typ, payload=None):
    p = json.dumps({"type": typ, "payload": payload or {}}).encode()
    n = len(p)
    hdr = b"\x81" + bytes([0x80 | (n if n < 126 else 126 if n < 65536 else 127)])
    if 126 <= n < 65536: hdr += struct.pack(">H", n)
    elif n >= 65536:     hdr += struct.pack(">Q", n)
    m = secrets.token_bytes(4)
    s.sendall(hdr + m + bytes(b ^ m[i % 4] for i, b in enumerate(p)))


class Client:
    def __init__(self):
        self.s, self.buf = ws_connect()
        send(self.s, "hello", {"v": 2, "auth": TOKEN, "client": CLIENT})
        ack = self.wait("hello.ack")
        assert "paste" in ack["payload"]["caps"], ack
        self.host = ack["payload"]["host"]

    def frames(self, deadline):
        while time.time() < deadline:
            while True:
                if len(self.buf) < 2: break
                b1, b2 = self.buf[0], self.buf[1]
                n = b2 & 0x7F; off = 2
                if n == 126: n = struct.unpack(">H", self.buf[2:4])[0]; off = 4
                elif n == 127: n = struct.unpack(">Q", self.buf[2:10])[0]; off = 10
                if len(self.buf) < off + n: break
                payload, self.buf = self.buf[off:off + n], self.buf[off + n:]
                if b1 & 0x0F in (1, 2):
                    yield json.loads(payload)
            self.s.settimeout(max(0.05, deadline - time.time()))
            try: self.buf += self.s.recv(65536)
            except (socket.timeout, OSError): return

    def wait(self, typ, timeout=4, where=lambda m: True):
        """First frame of `typ` matching `where`; frames skipped over are kept
        for later waits (e.g. a reset screen that lands before a windows push)."""
        pending = getattr(self, "pending", [])
        for i, msg in enumerate(pending):
            if msg.get("type") == typ and where(msg):
                self.pending = pending[:i] + pending[i + 1:]
                return msg
        for msg in self.frames(time.time() + timeout):
            if msg.get("type") == "error":
                print("   agent error:", msg["payload"])
            if msg.get("type") == typ and where(msg):
                return msg
            pending.append(msg)
            self.pending = pending
        raise AssertionError(f"no {typ} within {timeout}s")

    def screen(self, mode=None, timeout=4):
        m = self.wait("screen", timeout, lambda m: mode is None or m["payload"]["mode"] == mode)
        return base64.b64decode(m["payload"]["data"])

    def collect_screen(self, seconds):
        pending = getattr(self, "pending", [])
        out = b"".join(base64.b64decode(m["payload"]["data"]) for m in pending if m.get("type") == "screen")
        self.pending = [m for m in pending if m.get("type") != "screen"]
        for msg in self.frames(time.time() + seconds):
            if msg.get("type") == "screen":
                out += base64.b64decode(msg["payload"]["data"])
            else:
                self.pending.append(msg)
        return out

    def close(self):
        self.s.close()


def tmux(*args, check=False):
    return subprocess.run([TMUX, *args], capture_output=True, text=True, check=check).stdout


def fresh_session(name, cmd):
    tmux("kill-session", "-t", name)
    tmux("new-session", "-d", "-s", name, "-x", "80", "-y", "24", cmd, check=True)
    time.sleep(1.2)
    return tmux("display-message", "-p", "-t", name, "#{session_id}").strip()


def check_prime(name, setup_cmd, expect_alt, minsize=200):
    sid = fresh_session(name, setup_cmd)
    c = Client()
    send(c.s, "session.attach", {"id": sid, "cols": 60, "rows": 20})
    att = c.wait("session.attached")
    assert att["payload"]["session"]["id"] == sid, att
    first = c.screen("reset")
    size = tmux("display-message", "-p", "-t", sid, "#{pane_width}x#{pane_height}").strip()
    c.close()
    tmux("kill-session", "-t", name)
    alt = b"\x1b[?1049h" in first
    assert alt == expect_alt, f"{name}: alt-screen primed={alt}, expected {expect_alt}\n{first[:120]!r}"
    assert len(first) > minsize, f"{name}: frame too small ({len(first)}B) — pane content missing"
    assert size == "60x20", f"{name}: pane was {size}, expected 60x20 before the first paint"
    print(f"ok  {name}: {len(first)}B first frame, alt={alt}, pane sized to {size} before paint")
    return first


def check_windows_and_input():
    sid = fresh_session("pt_win", "bash --norc --noprofile")
    c = Client()
    send(c.s, "session.attach", {"id": sid, "cols": 60, "rows": 20})
    att = c.wait("session.attached")
    windows = att["payload"]["windows"]
    assert len(windows) == 1 and windows[0]["active"], windows
    c.screen("reset")

    # input → the shell echoes the marker back through %output
    marker = "POCKET_" + secrets.token_hex(3)
    send(c.s, "input", {"data": base64.b64encode(f"echo {marker}\r".encode()).decode()})
    out = c.collect_screen(1.5)
    assert marker.encode() in out, f"typed marker not echoed: {out[-200:]!r}"
    print("ok  input round-trip (send-keys -H)")

    # paste (bracketed paste is off in plain bash; the text must still land verbatim)
    pasted = "echo PASTE_" + secrets.token_hex(2)
    send(c.s, "paste", {"text": pasted + "\n"})
    out = c.collect_screen(1.5)
    assert pasted.split()[1].encode() in out, f"paste missing: {out[-200:]!r}"
    print("ok  paste (load-buffer + paste-buffer -p)")

    # windows: create → list has 2 and the new one is active; a reset frame follows
    send(c.s, "window.create")
    w = c.wait("windows", where=lambda m: len(m["payload"]["windows"]) == 2)["payload"]["windows"]
    c.screen("reset")
    new = [x for x in w if x["active"]][0]
    old = [x for x in w if not x["active"]][0]
    print(f"ok  window.create → {new['id']} active, reset frame")

    send(c.s, "window.rename", {"id": new["id"], "name": "renamed win"})
    w = c.wait("windows", where=lambda m: any(x["name"] == "renamed win" for x in m["payload"]["windows"]))
    print("ok  window.rename")

    send(c.s, "window.select", {"id": old["id"]})
    w = c.wait("windows", where=lambda m: [x for x in m["payload"]["windows"] if x["active"]][0]["id"] == old["id"])
    first = c.screen("reset")
    assert marker.encode() in first, "switching back did not re-prime the old window's content"
    print("ok  window.select → re-primed with the old window's content")

    send(c.s, "window.kill", {"id": new["id"]})
    c.wait("windows", where=lambda m: len(m["payload"]["windows"]) == 1)
    print("ok  window.kill")

    send(c.s, "ping", {"sentAt": 123.5})
    assert c.wait("pong")["payload"]["sentAt"] == 123.5
    print("ok  ping/pong")

    send(c.s, "session.detach")
    d = c.wait("session.detached")
    assert d["payload"]["reason"] == "requested", d
    size_opt = tmux("show-window-option", "-t", sid, "window-size").strip()
    assert "manual" not in size_opt, f"window-size still pinned after detach: {size_opt!r}"
    print("ok  session.detach → reason=requested, window-size unpinned")

    # killing the session from the Mac while attached → detached(sessionKilled)
    send(c.s, "session.attach", {"id": sid})
    c.wait("session.attached")
    tmux("kill-session", "-t", sid)
    d = c.wait("session.detached")
    assert d["payload"]["reason"] == "sessionKilled", d
    print("ok  kill-session on the Mac → detached(sessionKilled)")
    c.close()


def check_auth():
    s, rest = ws_connect()
    send(s, "hello", {"v": 2, "auth": "wrong-token-000000", "client": CLIENT})
    c = Client.__new__(Client); c.s, c.buf = s, rest
    e = c.wait("error")
    assert e["payload"]["code"] == "auth", e
    print("ok  wrong token → error(auth)")
    s.close()


f = check_prime("pt_alt", "vim -u NONE /tmp/pt_big.txt", True)
assert b"pt_big.txt" in f, "vim status line missing"
g = check_prime("pt_norm", "bash -c 'seq 1 300; sleep 60'", False)
assert b"300" in g, f"shell scrollback missing: {g[-200:]!r}"
assert g.count(b"\r\n") > 100, f"scrollback not captured ({g.count(b'\r\n')} lines)"
print("ok  scrollback captured:", g.count(b"\r\n"), "lines")
m = check_prime("pt_mouse", "bash -c \"printf '\\033[?1049h\\033[?1000h\\033[?1002h\\033[?1006hMOUSE-ON'; sleep 60\"", True, minsize=40)
assert b"\x1b[?1000h" in m and b"\x1b[?1006h" in m, f"mouse mode not primed: {m[:160]!r}"
print("ok  mouse reporting primed")
check_windows_and_input()
check_auth()
print("ALL OK")
