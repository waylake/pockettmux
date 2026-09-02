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

## 3. Nothing scrolls — not in a TUI, not in the shell scrollback

**Symptom:** Dragging on the terminal does nothing. Not in pi / Claude Code /
vim (no history revealed), and not in a plain shell either (no scrollback).
Several fixes aimed at the gesture recognizers changed nothing.

**Root cause — the phone's emulator never learns the pane's state, because
tmux control mode replays nothing.** `tmux -CC` relays only pane output that
happens *after* the control client attaches. Verified on tmux 3.7c with a raw
pty client: attach + `refresh-client` (and even `resize-window` +
`refresh-client -C`) produced **zero `%output` frames** for an idle pane, and
for a pane running vim produced 13.5 KB of repaint that contained **no
`?1049h` and no `?1006h`** — the app emitted those long before we attached.

So on the phone:

| SwiftTerm state | Reality | Consequence |
|---|---|---|
| `isCurrentBufferAlternate == false` | pane *is* on the alternate screen | `gestureRecognizerShouldBegin` returns false → **the swipe gesture never fires, ever** |
| `mouseMode == .off` | pi/Claude Code have SGR mouse on | can't tell "forward the wheel" from "scroll the buffer" |
| scrollback empty | pane has thousands of lines | native drag has nothing to show |
| TUI repaint lands in the *normal* buffer | belongs in the alt buffer | in-place repaint keeps `lines.count ≈ rows`, so the scroll view can't scroll either |

Every earlier attempt tuned the gesture plumbing (`require(toFail:)` direction,
`gestureRecognizerShouldBegin`), which was downstream of a gate that was
hard-wired to `false`. Fixing gestures could never work.

**How others handle it** (research, Sept 2026): the tmux wiki is explicit that
control mode leaves the initial paint to the client — *"It is up to the client
to update the content of the pane if necessary, for example using
capture-pane"* ([Control Mode](https://github.com/tmux/tmux/wiki/Control-Mode)).
iTerm2's tmux integration does exactly that; PocketTmux simply never did
([iTerm2 tmux integration](https://iterm2.com/documentation-tmux-integration.html)).

**Fix (`TmuxControl.primeScreen`).** tmux tracks all the missing state per
pane, so on attach the agent rebuilds it and hands it to the phone as the
first frame, before any live output:

- `#{alternate_on}` → `ESC[?1049h` (or `?1049l` first, to leave a stale one)
- `#{mouse_any_flag}` / `#{mouse_sgr_flag}` → `ESC[?1000h ?1002h ?1006h`
- `#{keypad_cursor_flag}` → `ESC[?1h` (DECCKM, so arrow keys are right)
- `capture-pane -p -e` → the visible screen, plus up to 2000 lines of history
  when the pane is on the *normal* buffer (the alternate screen has none)

Everything downstream then works off SwiftTerm's own, now-correct state
machine: the TUI's output lands in the alternate buffer, `?1049l` on quit
returns to the normal one, and the shell's scrollback is populated on arrival.

**Second cause, only visible once the first is fixed — a gesture race.** The
moment the emulator learns the app has mouse reporting on, SwiftTerm adds its
*own* `UIPanGestureRecognizer` (`panMouseHandler`), which forwards a drag as a
**click-drag**: button press, motion events, release. Two pans on one view with
no dependency race in undefined order; when SwiftTerm's won, the TUI got a
left-button drag (a text selection at best) and nothing scrolled — the finger
"dragged" but the content stayed put. Fix: the swipe pan's delegate returns
`true` from `gestureRecognizer(_:shouldBeRequiredToFailBy:)` for every other
pan on the view, so the scrollback pan *and* SwiftTerm's mouse pan wait for it.
On the normal screen the swipe pan fails in `gestureRecognizerShouldBegin`, so
they proceed untouched. (The old `tv.panGestureRecognizer.require(toFail:)`
line covered only the scrollback pan; the delegate method subsumes it.)

Confirmed on the iPhone 15 Pro by streaming the app's stdout — 14 swipes,
every one began with `alt=true` and a primed mouse mode
(`buttonEventTracking` = pi, `anyEvent` = Claude Code), ~100 wheel events
delivered, pi/Claude Code scrolled:

```sh
xcrun devicectl device process launch --console --terminate-existing \
  --device 0D5A0A22-5B84-51D7-B40F-49752A5E8F90 com.waylake.pockettmux
# CLIENT: swipe shouldBegin alt=true mouse=buttonEventTracking
# CLIENT: swipe up x2 wheel
```

**Swipe → scroll translation** (`TerminalCoordinator.sendScroll`), gated to the
alternate screen — where by definition there is no scrollback to drag:

- **App reads the mouse** (`mouseMode != .off`) → SGR wheel
  `ESC[<64;col;rowM` (up) / `65` (down). pi (`tuiMode: "fullscreen"`) and
  Claude Code parse these and scroll their own transcript. `tmux send-keys -H`
  delivers them to the pane — one hex number **per key**, so each byte is its
  own `%02x` arg (a single concatenated hex string is silently dropped).
- **App ignores the mouse** (less, man, htop, vim) → cursor up/down keys,
  which is what xterm's `alternateScroll` (DECSET 1007) does and the only
  thing those apps respond to.

Direction follows iOS, not the old code: dragging **down** pulls older content
into view (= wheel up). The previous mapping was inverted.

**pi has two TUI modes** (source: `@earendil-works/pi-tui`, `tuiMode` setting,
default `"regular"`):
- **`regular` (default)** → `TuiMainScreen`: renders to the normal buffer and
  relies on the *terminal's* scrollback. Over tmux `-CC` pi redraws in place,
  so the pane's scrollback doesn't accumulate, and pi doesn't read the mouse.
- **`fullscreen`** → `TuiAltScreen`: alternate screen + SGR mouse capture +
  a transcript `ScrollView`. This is the mode the swipe scrolls. Enable via
  `~/.pi/settings.json`: `{"tuiMode": "fullscreen"}` (or `/settings` →
  tui-mode, or `--tui-mode`). PgUp/PgDn also scroll the viewport there —
  SwiftTerm's accessory bar has both.

**Check:** `python3 scripts/check-attach-prime.py` (agent must be running).
It attaches over the real WebSocket to a vim pane, a shell pane and a
mouse-reporting pane, and asserts the first `screen` frame carries the right
alt-screen / mouse escapes and the pane's content.

