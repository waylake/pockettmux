import Foundation

/// pockettmuxd — the PocketTmux Mac agent.
///
///   pockettmuxd [--port 7682] [--token T]
///
/// Listens on 0.0.0.0 (LAN + Tailscale). Token: `--token` wins; otherwise
/// ~/.pockettmux/token is reused or created on first run. The phone must use
/// the same token, so keep that file between runs.
let arguments = CommandLine.arguments
var port: UInt16 = 7682
var token: String?

// Unbuffered stdout so `nohup ... > log` shows lifecycle logs in real time.
setbuf(stdout, nil)

var i = 1
while i < arguments.count {
    switch arguments[i] {
    case "--port":
        if i + 1 < arguments.count { port = UInt16(arguments[i + 1]) ?? 7682 }
        i += 2
    case "--token":
        if i + 1 < arguments.count { token = arguments[i + 1] }
        i += 2
    default:
        i += 1
    }
}

let tokenFile = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".pockettmux/token")

func loadOrCreateToken(override: String?) -> String {
    if let override, !override.isEmpty { return override }
    if let existing = try? String(contentsOf: tokenFile, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines),
        existing.count >= 16 { return existing }
    let alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    let t = String((0..<24).map { _ in alphabet.randomElement()! })
    try? FileManager.default.createDirectory(at: tokenFile.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    try? t.write(to: tokenFile, atomically: true, encoding: .utf8)
    return t
}

let server = AgentServer(port: port, token: loadOrCreateToken(override: token))
try server.start()

dispatchMain()
