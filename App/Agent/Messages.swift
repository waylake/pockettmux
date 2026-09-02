import Foundation

/// Wire protocol (v1). JSON text frames, `data` fields are base64 for byte safety.
/// Conforms to docs/ARCHITECTURE.md §5 and docs/PRODUCT-v1.md §3.

enum CMessage {
    case hello(auth: String, version: Int)
    case listSessions
    case createSession(name: String)
    case attachSession(id: String)
    case detach
    case destroySession(id: String)
    case input(data: Data)
    case resize(cols: Int, rows: Int)
    case ping
    case unknown(type: String)
}

enum JsonErr: Error { case malformed, badAuth }

enum CMessageDecoder {
    static func decode(_ data: Data) throws -> CMessage {
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any] else { throw JsonErr.malformed }
        let type = dict["type"] as? String ?? ""
        let payload = dict["payload"] as? [String: Any] ?? [:]
        switch type {
        case "hello":
            guard let auth = payload["auth"] as? String else { throw JsonErr.badAuth }
            return .hello(auth: auth, version: payload["v"] as? Int ?? 1)
        case "session.list":
            return .listSessions
        case "session.create":
            guard let name = payload["name"] as? String, !name.isEmpty else { throw JsonErr.malformed }
            return .createSession(name: name)
        case "session.attach":
            guard let id = payload["id"] as? String else { throw JsonErr.malformed }
            return .attachSession(id: id)
        case "session.detach":
            return .detach
        case "session.destroy":
            guard let id = payload["id"] as? String else { throw JsonErr.malformed }
            return .destroySession(id: id)
        case "input":
            guard let b64 = payload["data"] as? String, let d = Data(base64Encoded: b64) else { throw JsonErr.malformed }
            return .input(data: d)
        case "resize":
            guard let cols = payload["cols"] as? Int, let rows = payload["rows"] as? Int else { throw JsonErr.malformed }
            return .resize(cols: cols, rows: rows)
        case "ping":
            return .ping
        default:
            return .unknown(type: type)
        }
    }
}

enum Sender {
    static func json(_ type: String, _ payload: [String: Any] = [:], context: [String: Any] = [:]) -> Data {
        var obj: [String: Any] = ["type": type, "payload": payload]
        for (k, v) in context { obj[k] = v }
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
    }

    static func helloAck(agentVersion: String, tmuxVersion: String) -> Data {
        json("hello.ack", ["agent": agentVersion, "tmux": tmuxVersion, "caps": ["output.base64", "input.base64"]])
    }

    static func sessionList(_ sessions: [TmuxSessionInfo]) -> Data {
        json("session.list", ["sessions": sessions.map { s in
            ["id": s.id, "name": s.name, "windows": s.windows, "attached": s.attached,
             "created": s.created, "activity": s.activity] as [String: Any]
        }])
    }

    static func screen(mode: String, data: Data, session: String) -> Data {
        json("screen", ["mode": mode, "data": data.base64EncodedString()], context: ["session": session])
    }

    static func error(code: String, message: String) -> Data {
        json("error", ["code": code, "message": message])
    }

    static func exit(code: Int, message: String, session: String) -> Data {
        json("exit", ["code": code, "message": message], context: ["session": session])
    }

    static func pong() -> Data { json("pong") }
}
