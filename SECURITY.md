# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| 1.0.x | ✅ |
| 0.1.x | ❌ (protocol v1, rejected by the v1.0 agent) |

Fixes ship in the next patch release; there are no backports.

## Threat model (v1)

PocketTmux gives a phone a shell on your Mac. That is exactly as dangerous as it
sounds, so the trust boundary is deliberately small and documented:

- **Trust = same network + token.** A 32-character random token lives in
  `~/.pockettmux/token` (mode `0600`), is compared in constant time, and must be
  presented in the first frame; a wrong token gets `error{auth}` and a closed
  socket. The phone keeps its copy in the iOS Keychain.
- **No TLS in v1** ([ARCHITECTURE D7](docs/ARCHITECTURE.md#6-key-technical-decisions--alternatives)).
  Intended deployments are a home LAN and Tailscale, which is already encrypted.
  On a LAN, an attacker who can sniff your traffic can read the session and steal
  the token. TLS with a pinned certificate and per-device tokens are planned for
  [v1.2](docs/ROADMAP.md#v12--security--reach).
- **The agent is not sandboxed.** It execs your `tmux` and opens a pty — the
  App Sandbox makes that impossible. It runs as your user, with your privileges.
- **Anything the token holder can do, they can do as you**: read every pane,
  type into it, create and kill sessions. There is no read-only mode in v1.
- **The agent binds every interface** on its port (default 7682) so Tailscale and
  the LAN both work. It is *not* built to face the internet: never port-forward
  it, and prefer Tailscale over exposing the port.
- **Out of scope:** hostile networks, multi-user Macs (one agent, one token
  owner), and any deployment where the Mac itself is untrusted.

If a threat above is unacceptable for you, stop the agent (menu bar → toggle, or
quit the app) — no agent, no exposure.

## Reporting a vulnerability

Use GitHub's private reporting: **Security → Report a vulnerability** on
<https://github.com/waylake/pockettmux/security/advisories/new>. Please do not
open a public issue for anything exploitable.

Include the version (or commit), the platform, and the smallest reproduction you
have — a `scripts/check-attach-prime.py`-style script or a frame dump is ideal.
Expect a first response within a week; if a fix is warranted, the advisory and
the patch release go out together and you get credit unless you ask otherwise.
