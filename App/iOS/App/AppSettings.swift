import Foundation

/// `@AppStorage` keys and their defaults. Registered once at launch so code
/// that reads `UserDefaults` directly (the terminal coordinator) sees the
/// same defaults as the SwiftUI settings sheet.
enum AppSettings {
    static let fontSize = "terminal.fontSize"      // Int, 12…20
    static let haptics = "terminal.haptics"        // Bool
    static let keepAwake = "terminal.keepAwake"    // Bool

    static let fontRange = 12...20
    static let defaultFontSize = 14

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            fontSize: defaultFontSize,
            haptics: true,
            keepAwake: true
        ])
    }
}
