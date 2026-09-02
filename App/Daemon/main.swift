import Foundation
import PocketTmuxAgent
import PocketTmuxKit

/// pockettmuxd — the headless PocketTmux agent (same engine as the Mac app).
///
///   pockettmuxd [--port 7682] [--token T] [--name "My Mac"] [--no-bonjour]
///               [--no-keep-awake] [--tmux /path/to/tmux] [--regenerate-token]
///
/// Listens on every interface (LAN + Tailscale). The token comes from
/// `--token`, else ~/.pockettmux/token (created on first run and shared with
/// the Mac app and scripts/pair.sh).
struct Options {
    var port = WireProtocol.defaultPort
    var token: String?
    var name = HostInfo.computerName
    var bonjour = true
    var keepAwake = true
    var tmuxPath: String?
    var regenerateToken = false
    var showHelp = false

    init(_ args: ArraySlice<String>) {
        var it = args.makeIterator()
        while let arg = it.next() {
            switch arg {
            case "--port": port = it.next().flatMap(UInt16.init) ?? port
            case "--token": token = it.next()
            case "--name": name = it.next() ?? name
            case "--no-bonjour": bonjour = false
            case "--no-keep-awake": keepAwake = false
            case "--tmux": tmuxPath = it.next()
            case "--regenerate-token": regenerateToken = true
            case "-h", "--help": showHelp = true
            default:
                FileHandle.standardError.write(Data("unknown option \(arg)\n".utf8))
                showHelp = true
            }
        }
    }
}

let options = Options(CommandLine.arguments.dropFirst())
if options.showHelp {
    print("""
    pockettmuxd \(AgentInfo.version) — PocketTmux agent
      --port N            listen port (default \(WireProtocol.defaultPort))
      --token T           pairing token (default: ~/.pockettmux/token)
      --regenerate-token  write a fresh token to ~/.pockettmux/token and exit
      --name NAME         host name shown on the phone (default: this Mac's name)
      --no-bonjour        do not advertise \(WireProtocol.bonjourType) on the LAN
      --no-keep-awake     do not hold a sleep assertion while a phone is attached
      --tmux PATH         tmux binary (default: Homebrew / /usr/local / /usr/bin)
    """)
    exit(0)
}
if options.regenerateToken {
    let token = TokenStore.regenerate()
    print("new token written to \(TokenStore.fileURL.path): \(token)")
    exit(0)
}

setbuf(stdout, nil)   // nohup … > log shows lifecycle lines in real time

let token = options.token.map { $0.isEmpty ? TokenStore.loadOrCreate() : $0 } ?? TokenStore.loadOrCreate()
let configuration = AgentConfiguration(port: options.port, token: token, hostName: options.name,
                                       advertiseBonjour: options.bonjour, keepAwakeWhileAttached: options.keepAwake,
                                       tmuxPath: options.tmuxPath)
let log = AgentLog(echoToStandardOutput: true)
let server: AgentServer
do {
    server = try AgentServer(configuration: configuration, log: log)
    try server.start()
} catch {
    FileHandle.standardError.write(Data("pockettmuxd: \(error.localizedDescription)\n".utf8))
    exit(1)
}

server.onSnapshot = { snapshot in
    if let error = snapshot.lastError {
        FileHandle.standardError.write(Data("pockettmuxd: \(error)\n".utf8))
        exit(1)
    }
}

let addresses = HostInfo.addresses().map { "\($0.ip) (\($0.label))" }.joined(separator: ", ")
log.info("reachable at: \(addresses.isEmpty ? "no interface up" : addresses) — token \(token.prefix(4))…")

// exit() from a raw signal handler is not safe (it tears down GCD from a
// signal context); route the signals through dispatch sources instead.
let signalSources: [DispatchSourceSignal] = [SIGINT, SIGTERM].map { sig in
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler {
        server.stop()
        exit(0)
    }
    source.resume()
    return source
}
dispatchMain()
