import Foundation

/// Wire protocol version. Bumped when a frame changes shape; the agent
/// rejects a `hello` whose `v` it does not speak.
public enum WireProtocol {
    public static let version = 2
    /// Bonjour service type advertised by the Mac agent.
    public static let bonjourType = "_pockettmux._tcp"
    /// Default agent port (7681 stays reserved for the ttyd prototype path).
    public static let defaultPort: UInt16 = 7682
    /// WebSocket path the agent answers on.
    public static let path = "/ws"
}

/// Who is connecting — shown in the Mac app's client list.
public struct ClientIdentity: Codable, Equatable, Hashable, Sendable {
    public var name: String      // "Doyeon's iPhone"
    public var model: String     // "iPhone15,2"
    public var app: String       // "PocketTmux iOS 1.0.0"

    public init(name: String, model: String, app: String) {
        self.name = name
        self.model = model
        self.app = app
    }
}

/// Who answered — shown in the phone's status/host list.
public struct HostIdentity: Codable, Equatable, Hashable, Sendable {
    public var name: String      // "Doyeon's MacBook Pro"
    public var agent: String     // agent version
    public var tmux: String      // "tmux 3.7c"

    public init(name: String, agent: String, tmux: String) {
        self.name = name
        self.agent = agent
        self.tmux = tmux
    }
}

/// A tmux session as surfaced by `tmux list-sessions -F`.
public struct SessionInfo: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: String              // "$1"
    public var name: String
    public var windows: Int
    public var attached: Int           // clients attached (Mac terminals + phones)
    public var created: TimeInterval   // epoch seconds
    public var activity: TimeInterval  // epoch seconds

    public init(id: String, name: String, windows: Int, attached: Int,
                created: TimeInterval, activity: TimeInterval) {
        self.id = id
        self.name = name
        self.windows = windows
        self.attached = attached
        self.created = created
        self.activity = activity
    }
}

/// A tmux window inside the attached session, from `tmux list-windows -F`.
public struct WindowInfo: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: String        // "@3"
    public var index: Int
    public var name: String
    public var active: Bool
    public var panes: Int

    public init(id: String, index: Int, name: String, active: Bool, panes: Int) {
        self.id = id
        self.index = index
        self.name = name
        self.active = active
        self.panes = panes
    }
}

public enum ScreenMode: String, Codable, Sendable {
    /// Full repaint: the emulator should treat this as the whole pane
    /// (attach, window switch, reconnect).
    case reset
    /// Incremental pane output.
    case update
}

public enum ErrorCode: String, Codable, Sendable {
    case auth
    case badFrame = "bad_frame"
    case unsupported
    case tmux
    case notAttached = "not_attached"
}

/// Why the control client left the session.
public enum DetachReason: String, Codable, Sendable {
    case requested          // the phone asked
    case sessionKilled      // session gone (kill-session / tmux server exit)
    case replaced           // another attach from the same connection
    case controlExited      // tmux -CC ended for some other reason
}
