# PocketTmux — Troubleshooting

Field notes on real failures and the research behind each fix. Verified against
tmux 3.7c and the live agent (reproduced with a raw WebSocket client replaying
the phone's frames).

## 1. Attach shows "Session ended" and a black screen

**Symptom:** Tap a session on the phone → the agent answers `exit` (`Session
ended`) → nothing renders, keyboard input goes nowhere.

**Root cause — duplicate `session.attach`.** The phone sent the attach **twice**:
once from `SessionListView`'s row tap (`client.attach(s)`), once from
`TerminalScreen.appearOnce` (which re-attaches "idempotently"). Each
`session.attach` makes the agent `killChild()` + respawn a fresh `tmux -CC`
control client. When a second control client takes over, the tmux server emits
`%exit` for the first → the agent relays `exit` → the app shows *Session ended*.
Reproduced: single attach → clean; two attaches 150 ms apart → `exit` (see
`scripts/` + the protocol docs).

**Fix (v1):** two layers.
- `AgentClient.attach(_:)` dedupes — it keeps `pendingAttach` (which also
  survives reconnects) and only sends `session.attach` when the target session
  actually changed while connected. `helloAck` re-attaches via the same deduped
  path, so reconnect re-attach still works.
- `Connection.dispatch(.attachSession)` ignores an attach for the session it's
  already showing, so older app builds that still double-send are safe too.

## 2. The Mac tmux window flashes to the phone size and back

**Symptom:** While attaching, the Mac terminal showing the session briefly
shrinks to the phone's size, then back.

**Why it happens.** A tmux session window has **one size shared by all attached
clients** (default `window-size latest` — the most recently active client
dictates it). The old agent forced sizes on attach:
`refresh-client -C 2x2` then `refresh-client -C 80x24`. Both resize the shared
window, so the Mac terminal visibly jumps to 2×2 and then 80×24 on every attach.
The duplicate-attach bug (§1) made this worse: two kill/respawn cycles in a row
= the "briefly changes, briefly returns" oscillation.

**How others handle it** (research, Sept 2026):
- **iTerm2's tmux integration** silently sets `window-size manual` so its
  control client's size never dictates session windows
  ([TmuxController.m](https://gitlab.com/gnachman/iterm2/-/blob/master/sources/TmuxController.m)).
  Downside: with `manual` the phone is **clamped to the window's current size**
  (a 200×50 window renders 200 columns on the phone), so it is not a good fit
  when the *phone* is the one driving.
- **`window-size largest`** pins the window to the largest client — protects a
  big Mac window from a small phone, same clamping tradeoff.
- **`resize-window -A`** resizes the window to the largest client; sets manual
  sizing, needs re-running after each resize.
- **`tmux attach -d`** force-detaches existing clients — not applicable; we
  want to coexist with the Mac client.

**Fix (v1):** two pieces.
- **No forced sizes on attach.** The control client inherits the window's
  current size and a plain `refresh-client` forces the initial full repaint.
- **Pin `window-size manual` for the duration of the attach** (the same thing
  iTerm2 does), and on the phone's `resize` run `tmux resize-window` to the
  phone's size instead of `refresh-client -C`. With `manual` the window no
  longer bounces between the Mac's and the phone's size while attached — the
  phone renders at a readable phone-sized window, the Mac shows that size
  steadily, and on detach the option is unset so the Mac client re-asserts its
  own size. (`refresh-client -C` alone is ignored under `manual`, hence the
  explicit `resize-window`.)
