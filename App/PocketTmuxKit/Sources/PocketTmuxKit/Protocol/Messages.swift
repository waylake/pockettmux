import Foundation

/// Frames the phone sends to the agent. One JSON object per WebSocket text
/// frame: `{"type": "<name>", "payload": {…}}`. Byte payloads are base64.
public enum ClientMessage: Equatable, Sendable {
    /// Must be the first frame. `v` is `WireProtocol.version`.
    case hello(auth: String, client: ClientIdentity)
    case sessionList
    case sessionCreate(name: String)
    case sessionRename(id: String, name: String)
    /// `cols`/`rows` are the phone's terminal size when already known, so the
    /// agent can size the window *before* the first paint (see ScreenPrimer).
    case sessionAttach(id: String, cols: Int?, rows: Int?)
    case sessionDetach
    case sessionKill(id: String)
    case windowSelect(id: String)
    case windowCreate
    case windowKill(id: String)
    case windowRename(id: String, name: String)
    /// Raw keystroke bytes for the active pane.
    case input(Data)
    /// Text pasted with tmux bracketed-paste semantics (no per-key storm).
    case paste(String)
    case resize(cols: Int, rows: Int)
    /// Round-trip probe; the agent echoes `sentAt` in `pong`.
    case ping(sentAt: Double)
}

/// Frames the agent sends to the phone.
public enum ServerMessage: Equatable, Sendable {
    case helloAck(host: HostIdentity, capabilities: [String])
    case sessionList([SessionInfo])
    /// The control client is attached; `windows` is the session's window list.
    case sessionAttached(session: SessionInfo, windows: [WindowInfo])
    case sessionDetached(reason: DetachReason)
    /// Window list of the attached session changed (add/close/rename/select).
    case windows(sessionID: String, windows: [WindowInfo])
    case screen(mode: ScreenMode, data: Data)
    case pong(sentAt: Double)
    case error(code: ErrorCode, message: String)
}

public enum WireError: Error, Equatable {
    case malformed
    /// A well-formed frame of a type this side does not know. Receivers
    /// ignore these (forward compatibility), they are not protocol errors.
    case unknownType(String)
}

// MARK: - Codec

public enum WireCodec {
    public static func encode(_ message: ClientMessage) -> Data {
        encodeFrame(message)
    }

    public static func encode(_ message: ServerMessage) -> Data {
        encodeFrame(message)
    }

    public static func decodeClient(_ data: Data) throws -> ClientMessage {
        try decodeFrame(data)
    }

    public static func decodeServer(_ data: Data) throws -> ServerMessage {
        try decodeFrame(data)
    }

    private static func encodeFrame<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        // Frames are built from our own value types; an encoding failure is a
        // programming error, not a runtime condition.
        return (try? encoder.encode(value)) ?? Data("{}".utf8)
    }

    private static func decodeFrame<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as WireError {
            throw error
        } catch {
            throw WireError.malformed
        }
    }
}

// MARK: - Client frames

private enum FrameKeys: String, CodingKey { case type, payload }

private struct Empty: Codable {}
private struct IDPayload: Codable { var id: String }
private struct AttachPayload: Codable { var id: String; var cols: Int?; var rows: Int? }
private struct NamePayload: Codable { var name: String }
private struct IDNamePayload: Codable { var id: String; var name: String }
private struct DataPayload: Codable { var data: Data }        // base64 via JSONEncoder
private struct TextPayload: Codable { var text: String }
private struct SizePayload: Codable { var cols: Int; var rows: Int }
private struct PingPayload: Codable { var sentAt: Double }
private struct HelloPayload: Codable { var v: Int; var auth: String; var client: ClientIdentity }

extension ClientMessage: Codable {
    private var typeName: String {
        switch self {
        case .hello: return "hello"
        case .sessionList: return "session.list"
        case .sessionCreate: return "session.create"
        case .sessionRename: return "session.rename"
        case .sessionAttach: return "session.attach"
        case .sessionDetach: return "session.detach"
        case .sessionKill: return "session.kill"
        case .windowSelect: return "window.select"
        case .windowCreate: return "window.create"
        case .windowKill: return "window.kill"
        case .windowRename: return "window.rename"
        case .input: return "input"
        case .paste: return "paste"
        case .resize: return "resize"
        case .ping: return "ping"
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: FrameKeys.self)
        try c.encode(typeName, forKey: .type)
        switch self {
        case .hello(let auth, let client):
            try c.encode(HelloPayload(v: WireProtocol.version, auth: auth, client: client), forKey: .payload)
        case .sessionList, .sessionDetach, .windowCreate:
            try c.encode(Empty(), forKey: .payload)
        case .sessionCreate(let name):
            try c.encode(NamePayload(name: name), forKey: .payload)
        case .sessionRename(let id, let name), .windowRename(let id, let name):
            try c.encode(IDNamePayload(id: id, name: name), forKey: .payload)
        case .sessionAttach(let id, let cols, let rows):
            try c.encode(AttachPayload(id: id, cols: cols, rows: rows), forKey: .payload)
        case .sessionKill(let id), .windowSelect(let id), .windowKill(let id):
            try c.encode(IDPayload(id: id), forKey: .payload)
        case .input(let data):
            try c.encode(DataPayload(data: data), forKey: .payload)
        case .paste(let text):
            try c.encode(TextPayload(text: text), forKey: .payload)
        case .resize(let cols, let rows):
            try c.encode(SizePayload(cols: cols, rows: rows), forKey: .payload)
        case .ping(let sentAt):
            try c.encode(PingPayload(sentAt: sentAt), forKey: .payload)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: FrameKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "hello":
            let p = try c.decode(HelloPayload.self, forKey: .payload)
            guard p.v == WireProtocol.version else { throw WireError.unknownType("hello v\(p.v)") }
            self = .hello(auth: p.auth, client: p.client)
        case "session.list": self = .sessionList
        case "session.create": self = .sessionCreate(name: try c.decode(NamePayload.self, forKey: .payload).name)
        case "session.rename":
            let p = try c.decode(IDNamePayload.self, forKey: .payload)
            self = .sessionRename(id: p.id, name: p.name)
        case "session.attach":
            let p = try c.decode(AttachPayload.self, forKey: .payload)
            self = .sessionAttach(id: p.id, cols: p.cols, rows: p.rows)
        case "session.detach": self = .sessionDetach
        case "session.kill": self = .sessionKill(id: try c.decode(IDPayload.self, forKey: .payload).id)
        case "window.select": self = .windowSelect(id: try c.decode(IDPayload.self, forKey: .payload).id)
        case "window.create": self = .windowCreate
        case "window.kill": self = .windowKill(id: try c.decode(IDPayload.self, forKey: .payload).id)
        case "window.rename":
            let p = try c.decode(IDNamePayload.self, forKey: .payload)
            self = .windowRename(id: p.id, name: p.name)
        case "input": self = .input(try c.decode(DataPayload.self, forKey: .payload).data)
        case "paste": self = .paste(try c.decode(TextPayload.self, forKey: .payload).text)
        case "resize":
            let p = try c.decode(SizePayload.self, forKey: .payload)
            self = .resize(cols: p.cols, rows: p.rows)
        case "ping": self = .ping(sentAt: try c.decode(PingPayload.self, forKey: .payload).sentAt)
        default: throw WireError.unknownType(type)
        }
    }
}

// MARK: - Server frames

private struct HelloAckPayload: Codable { var host: HostIdentity; var caps: [String] }
private struct SessionsPayload: Codable { var sessions: [SessionInfo] }
private struct AttachedPayload: Codable { var session: SessionInfo; var windows: [WindowInfo] }
private struct DetachedPayload: Codable { var reason: DetachReason }
private struct WindowsPayload: Codable { var sessionID: String; var windows: [WindowInfo] }
private struct ScreenPayload: Codable { var mode: ScreenMode; var data: Data }
private struct ErrorPayload: Codable { var code: ErrorCode; var message: String }

extension ServerMessage: Codable {
    private var typeName: String {
        switch self {
        case .helloAck: return "hello.ack"
        case .sessionList: return "session.list"
        case .sessionAttached: return "session.attached"
        case .sessionDetached: return "session.detached"
        case .windows: return "windows"
        case .screen: return "screen"
        case .pong: return "pong"
        case .error: return "error"
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: FrameKeys.self)
        try c.encode(typeName, forKey: .type)
        switch self {
        case .helloAck(let host, let caps):
            try c.encode(HelloAckPayload(host: host, caps: caps), forKey: .payload)
        case .sessionList(let sessions):
            try c.encode(SessionsPayload(sessions: sessions), forKey: .payload)
        case .sessionAttached(let session, let windows):
            try c.encode(AttachedPayload(session: session, windows: windows), forKey: .payload)
        case .sessionDetached(let reason):
            try c.encode(DetachedPayload(reason: reason), forKey: .payload)
        case .windows(let sessionID, let windows):
            try c.encode(WindowsPayload(sessionID: sessionID, windows: windows), forKey: .payload)
        case .screen(let mode, let data):
            try c.encode(ScreenPayload(mode: mode, data: data), forKey: .payload)
        case .pong(let sentAt):
            try c.encode(PingPayload(sentAt: sentAt), forKey: .payload)
        case .error(let code, let message):
            try c.encode(ErrorPayload(code: code, message: message), forKey: .payload)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: FrameKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "hello.ack":
            let p = try c.decode(HelloAckPayload.self, forKey: .payload)
            self = .helloAck(host: p.host, capabilities: p.caps)
        case "session.list":
            self = .sessionList(try c.decode(SessionsPayload.self, forKey: .payload).sessions)
        case "session.attached":
            let p = try c.decode(AttachedPayload.self, forKey: .payload)
            self = .sessionAttached(session: p.session, windows: p.windows)
        case "session.detached":
            self = .sessionDetached(reason: try c.decode(DetachedPayload.self, forKey: .payload).reason)
        case "windows":
            let p = try c.decode(WindowsPayload.self, forKey: .payload)
            self = .windows(sessionID: p.sessionID, windows: p.windows)
        case "screen":
            let p = try c.decode(ScreenPayload.self, forKey: .payload)
            self = .screen(mode: p.mode, data: p.data)
        case "pong":
            self = .pong(sentAt: try c.decode(PingPayload.self, forKey: .payload).sentAt)
        case "error":
            let p = try c.decode(ErrorPayload.self, forKey: .payload)
            self = .error(code: p.code, message: p.message)
        default:
            throw WireError.unknownType(type)
        }
    }
}
