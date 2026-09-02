import SwiftUI
import PocketTmuxKit

/// Add / edit a Mac: scan the pairing QR, or type NAME / HOST / PORT / TOKEN.
struct AddHostSheet: View {
    enum Mode {
        case add
        case nearby(DiscoveredHost)
        case edit(HostProfile)
    }

    private enum Tab: String, CaseIterable, Identifiable {
        case scan, manual
        var id: String { rawValue }
        var title: String { self == .scan ? L.scanQR : L.enterManually }
    }

    let mode: Mode
    let onSave: (HostProfile, _ connect: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab
    @State private var name: String
    @State private var host: String
    @State private var port: String
    @State private var token: String
    @State private var cameraDenied = false
    @FocusState private var focused: Field?

    private enum Field { case name, host, port, token }

    init(mode: Mode, onSave: @escaping (HostProfile, _ connect: Bool) -> Void) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .add:
            _tab = State(initialValue: .scan)
            _name = State(initialValue: "")
            _host = State(initialValue: "")
            _port = State(initialValue: String(WireProtocol.defaultPort))
            _token = State(initialValue: "")
        case .nearby(let found):
            _tab = State(initialValue: .manual)
            _name = State(initialValue: found.name)
            _host = State(initialValue: found.host)
            _port = State(initialValue: String(found.port))
            _token = State(initialValue: "")
        case .edit(let profile):
            _tab = State(initialValue: .manual)
            _name = State(initialValue: profile.name)
            _host = State(initialValue: profile.host)
            _port = State(initialValue: String(profile.port))
            _token = State(initialValue: profile.token)
        }
    }

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { t in Text(t.title).tag(t) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                switch tab {
                case .scan: scanner
                case .manual: form
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(isEdit ? L.editMac : L.addMac)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.cancel) { dismiss() }
                }
                if isEdit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L.save) { commit(connect: false) }.disabled(validationError != nil)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Scan

    private var scanner: some View {
        VStack(spacing: 0) {
            QRScannerView(onDenied: { cameraDenied = true }, onFound: { payload in
                guard let pairing = PairingPayload(string: payload) else { return }
                apply(pairing)
            })
            .onAppear { cameraDenied = false }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radius)
                    .stroke(Theme.vermilion, lineWidth: 2)
                    .frame(width: 220, height: 220)
                    .opacity(0.9)
            }
            .background(Theme.bg)
            Text(cameraDenied ? L.cameraDenied : L.scanHint)
                .font(Theme.mono(11))
                .foregroundStyle(cameraDenied ? Theme.yamabuki : Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Theme.surface)
        }
    }

    /// A scanned QR is a complete pairing: save and connect at once.
    private func apply(_ pairing: PairingPayload) {
        let profile: HostProfile
        if case .edit(let existing) = mode {
            profile = existing.applying(pairing)
        } else {
            var p = HostProfile(pairing: pairing)
            if pairing.name == nil, !name.isEmpty { p.name = name }
            profile = p
        }
        onSave(profile, true)
    }

    // MARK: - Manual

    private var form: some View {
        ScrollView {
            VStack(spacing: 16) {
                field("NAME", text: $name, placeholder: "MacBook Pro", field: .name)
                field("HOST", text: $host, placeholder: "100.67.189.40", field: .host, keyboard: .URL)
                HStack(alignment: .top, spacing: 12) {
                    field("PORT", text: $port, placeholder: String(WireProtocol.defaultPort), field: .port,
                          keyboard: .numberPad)
                        .frame(width: 110)
                    field("TOKEN", text: $token, placeholder: "token", field: .token, secure: true)
                }
                if let error = validationError, touchedAny {
                    Text(error)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.yamabuki)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button { commit(connect: true) } label: {
                    Text(L.saveAndConnect)
                        .font(Theme.mono(14, .semibold))
                        .tracking(1.5)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(validationError == nil ? Theme.vermilion : Theme.surface2)
                        .foregroundStyle(validationError == nil ? Theme.paper : Theme.muted)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                }
                .buttonStyle(.plain)
                .disabled(validationError != nil)
                .padding(.top, 8)
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String, field: Field,
                       keyboard: UIKeyboardType = .default, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(keyboard)
            .font(Theme.mono(15))
            .foregroundStyle(Theme.paper)
            .focused($focused, equals: field)
            .padding(12)
            .background(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.surface2, lineWidth: 1))
        }
    }

    private var touchedAny: Bool { !host.isEmpty || !token.isEmpty }

    private var validationError: String? {
        if host.trimmingCharacters(in: .whitespaces).isEmpty { return L.invalidHost }
        guard let p = UInt16(port.trimmingCharacters(in: .whitespaces)), p > 0 else { return L.invalidPort }
        if token.trimmingCharacters(in: .whitespaces).isEmpty { return L.invalidTokenField }
        return nil
    }

    private func commit(connect: Bool) {
        guard validationError == nil, let portValue = UInt16(port.trimmingCharacters(in: .whitespaces)) else { return }
        let h = host.trimmingCharacters(in: .whitespaces)
        let n = name.trimmingCharacters(in: .whitespaces)
        var profile: HostProfile
        if case .edit(let existing) = mode {
            profile = existing
        } else {
            profile = HostProfile(name: h, host: h, token: "")
        }
        profile.name = n.isEmpty ? h : n
        profile.host = h
        profile.port = portValue
        profile.token = token.trimmingCharacters(in: .whitespaces)
        onSave(profile, connect)
    }
}
