import SwiftUI
import PocketTmuxKit

/// Terminal preferences and About, presented as a standard SwiftUI form.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.fontSize) private var fontSize = AppSettings.defaultFontSize
    @AppStorage(AppSettings.haptics) private var haptics = true
    @AppStorage(AppSettings.keepAwake) private var keepAwake = true

    private static let repoURL = URL(string: "https://github.com/waylake/pockettmux")!

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L.terminal) {
                    Stepper(value: $fontSize, in: AppSettings.fontRange) {
                        LabeledContent(L.fontSize) {
                            Text("\(fontSize) pt")
                                .monospacedDigit()
                        }
                    }
                    Toggle(L.haptics, isOn: $haptics)
                    Toggle(L.keepAwake, isOn: $keepAwake)
                }

                Section(L.about) {
                    LabeledContent(L.version, value: version)
                    LabeledContent(L.protocolLabel, value: "v\(WireProtocol.version)")
                    Link(destination: Self.repoURL) {
                        LabeledContent(L.sourceCode, value: "github.com/waylake/pockettmux")
                    }
                    LabeledContent(L.license, value: "")
                }
            }
            .navigationTitle(L.settings)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.done) { dismiss() }
                }
            }
        }
    }
}
