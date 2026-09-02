import SwiftUI
import PocketTmuxKit

/// Settings sheet: terminal preferences (`@AppStorage`) and About.
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
            List {
                Section {
                    Stepper(value: $fontSize, in: AppSettings.fontRange) {
                        row(L.fontSize, value: "\(fontSize) pt")
                    }
                    Toggle(isOn: $haptics) { label(L.haptics) }
                    Toggle(isOn: $keepAwake) { label(L.keepAwake) }
                } header: {
                    SectionLabel(L.terminal)
                }
                .listRowBackground(Theme.surface)
                .listRowSeparatorTint(Theme.surface2)

                Section {
                    row(L.version, value: version)
                    row(L.protocolLabel, value: "v\(WireProtocol.version)")
                    Link(destination: Self.repoURL) {
                        row(L.sourceCode, value: "github.com/waylake/pockettmux")
                    }
                    row(L.license, value: "")
                } header: {
                    SectionLabel(L.about)
                }
                .listRowBackground(Theme.surface)
                .listRowSeparatorTint(Theme.surface2)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .tint(Theme.vermilion)
            .navigationTitle(L.settings)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.done) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(Theme.paper)
    }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            label(title)
            Spacer()
            Text(value)
                .font(Theme.mono(12))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
    }
}
