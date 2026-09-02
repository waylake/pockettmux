import Foundation

/// Wire DTOs (mirror the agent protocol; docs/PRODUCT-v1.md §3).
/// `data` fields travel as base64. All types are value types for SwiftUI.

struct SessionInfo: Codable, Equatable, Identifiable, Sendable {
    let id: String       // "$1"
    let name: String
    let windows: Int
    let attached: Int
    let created: TimeInterval
    let activity: TimeInterval
}

/// Subset of agent→client message types the app consumes.
enum ServerEvent {
    case helloAck(tmux: String)
    case sessionList([SessionInfo])
    case screen(mode: String, data: Data)
    case sessionAttached(id: String, name: String)
    case exit(message: String)
    case error(code: String, message: String)
}

enum WireCoder {
    /// `{ "type": "...", "payload": {...} }` → message
    static func decode(_ text: String) -> ServerEvent? {
        guard let o = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let payload = o["payload"] as? [String: Any] else { return nil }
        switch o["type"] as? String {
        case "hello.ack":
            return .helloAck(tmux: payload["tmux"] as? String ?? "?")
        case "session.list":
            var sessions: [SessionInfo] = []
            if let arr = payload["sessions"] as? [[String: Any]] {
                for s in arr {
                    if let id = s["id"] as? String, let name = s["name"] as? String,
                       let windows = s["windows"] as? Int, let attached = s["attached"] as? Int {
                        sessions.append(SessionInfo(id: id, name: name, windows: windows,
                                                    attached: attached,
                                                    created: s["created"] as? TimeInterval ?? 0,
                                                    activity: s["activity"] as? TimeInterval ?? 0))
                    }
                }
            }
            return .sessionList(sessions)
        case "screen":
            guard let mode = payload["mode"] as? String,
                  let b64 = payload["data"] as? String,
                  let data = Data(base64Encoded: b64) else { return nil }
            return .screen(mode: mode, data: data)
        case "session.attached":
            return .sessionAttached(id: payload["id"] as? String ?? "",
                                    name: payload["name"] as? String ?? "")
        case "exit":
            return .exit(message: payload["message"] as? String ?? "")
        case "error":
            return .error(code: payload["code"] as? String ?? "",
                          message: payload["message"] as? String ?? "")
        default:
            return nil
        }
    }

    static func envelope(type: String, payload: [String: Any]) -> String {
        let o: [String: Any] = ["type": type, "payload": payload]
        guard let d = try? JSONSerialization.data(withJSONObject: o),
              let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }
}
