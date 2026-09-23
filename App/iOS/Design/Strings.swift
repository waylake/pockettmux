import Foundation

/// User-facing copy. The interface uses Apple's standard labels and sentence
/// case; monospaced styling is reserved for technical values in the UI.
enum L { // swiftlint:disable:this type_name
    // App
    static let appName        = "PocketTmux"
    static let macs           = "Macs"

    // Connection
    static let connect        = "Connect"
    static let disconnect     = "Disconnect"
    static let connected      = "Connected"
    static let disconnected   = "Disconnected"
    static let reconnecting   = "Reconnecting…"
    static let connecting     = "Connecting…"
    static let invalidToken   = "Auth failed — check the token"
    static let cantReach      = "Unreachable — check host and port"

    // Macs
    static let savedMacs      = "Saved Macs"
    static let nearbyMacs     = "Nearby Macs"
    static let tailscaleNote  = "Macs on Tailscale don't appear here — scan the QR instead."
    static let pair           = "Pair"
    static let addMac         = "Add Mac"
    static let editMac        = "Edit Mac"
    static let rename         = "Rename"
    static let edit           = "Edit"
    static let forget         = "Forget"
    static let delete         = "Delete"
    static let cancel         = "Cancel"
    static let save           = "Save"
    static let saveAndConnect = "Save & Connect"
    static let scanQR         = "Scan QR"
    static let enterManually  = "Enter manually"
    static let neverConnected = "never connected"
    static let onboardingTitle = "Pair Your Mac"
    static let onboardingDescription =
        "Open PocketTmux on your Mac, choose Pair iPhone, then scan the code shown there."
    static let cameraDenied   = "Camera access is off — enable it in Settings → PocketTmux, or enter the details manually."
    static let scanHint       = "Point the camera at the QR shown by PocketTmux on your Mac."
    static let forgetBody     = "The saved address and token will be removed from this iPhone."
    static func forgetTitle(_ name: String) -> String { "Forget \(name)?" }
    static let invalidHost    = "Host is required"
    static let invalidPort    = "Port must be 1–65535"
    static let invalidTokenField = "Token is required"

    // Sessions
    static let sessions       = "Sessions"
    static let newSession     = "New session"
    static let sessionName    = "Name of the new tmux session"
    static let renameSession  = "Rename session"
    static let kill           = "Kill"
    static let emptySessions  = "No tmux Sessions"
    static let emptyDescription = "Create a session to start using tmux from this Mac."
    static let attachedOnIPhone = "Attached on iPhone"
    static let invalidName    = "Names can't contain : or . or start with -"
    static func killSessionTitle(_ name: String) -> String { "Kill session \(name)?" }
    static let killSessionBody = "The session and its windows will be killed. This cannot be undone."

    // Terminal
    static let newWindow      = "New Window"
    static let windowsMenu    = "Choose Window"
    static let panesMenu      = "Choose Pane"
    static let sessionLayout  = "Session Layout"
    static let window         = "Window"
    static let pane           = "Pane"
    static let noWindows      = "No windows"
    static let hideKeyboard   = "Hide Keyboard"
    static let more           = "More"
    static let renameWindow   = "Rename Window"
    static let killWindow     = "Kill window"
    static func killWindowTitle(_ name: String) -> String { "Kill window \(name)?" }
    static let killWindowBody = "Every pane in the window will be killed."
    static let detach         = "Detach"
    static let paste          = "Paste"
    static let fontSmaller    = "Font size −"
    static let fontLarger     = "Font size +"
    static let sessionEndedOnMac = "Session ended on the Mac"
    static let sessionLost    = "Connection to the session was lost"
    static let clipboardEmpty = "Clipboard is empty"

    // Settings
    static let settings       = "Settings"
    static let terminal       = "Terminal"
    static let fontSize       = "Font size"
    static let haptics        = "Haptics on bell"
    static let keepAwake      = "Keep screen awake in terminal"
    static let about          = "About"
    static let version        = "Version"
    static let protocolLabel  = "Protocol"
    static let sourceCode     = "Source code"
    static let license        = "MIT License"
    static let done           = "Done"

    // Formatting
    static func windows(_ n: Int) -> String { n == 1 ? "1 window" : "\(n) windows" }
    static func clients(_ n: Int) -> String { n == 1 ? "1 attached" : "\(n) attached" }
    static func rtt(_ seconds: TimeInterval) -> String { "\(Int((seconds * 1000).rounded())) ms" }

    /// Compact relative time ("just now", "5m ago", "2h ago", "3d ago").
    static func ago(_ date: Date) -> String {
        let d = max(0, Date().timeIntervalSince(date))
        if d < 60 { return "just now" }
        if d < 3600 { return "\(Int(d / 60))m ago" }
        if d < 86400 { return "\(Int(d / 3600))h ago" }
        return "\(Int(d / 86400))d ago"
    }

    static func ago(_ epoch: TimeInterval) -> String {
        ago(Date(timeIntervalSince1970: epoch))
    }
}
