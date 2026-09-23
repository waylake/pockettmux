import SwiftUI
import PocketTmuxKit

/// Add or edit a Mac. The form and scanner live in a standard sheet; validation,
/// labels, controls, and the confirm action are supplied by SwiftUI.
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
            Form {
                Section {
                    Picker("Pairing method", selection: $tab) {
                        ForEach(Tab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                switch tab {
                case .scan:
                    scanner
                case .manual:
                    manualEntry
                }
            }
            .navigationTitle(isEdit ? L.editMac : L.addMac)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEdit ? L.save : L.saveAndConnect) {
                        commit(connect: !isEdit)
                    }
                    .disabled(validationError != nil)
                }
            }
        }
    }

    // MARK: - Scan

    private var scanner: some View {
        Section {
            QRScannerView(onDenied: { cameraDenied = true }, onFound: { payload in
                guard let pairing = PairingPayload(string: payload) else { return }
                apply(pairing)
            })
            .onAppear { cameraDenied = false }
            .frame(maxWidth: .infinity)
            .frame(height: 340)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: 220, height: 220)
            }
            .listRowInsets(EdgeInsets())
        } header: {
            Text(L.scanQR)
        } footer: {
            if cameraDenied {
                Label(L.cameraDenied, systemImage: "camera.fill")
                    .foregroundStyle(.orange)
            } else {
                Text(L.scanHint)
            }
        }
    }

    /// A scanned QR is a complete pairing: save and connect at once.
    private func apply(_ pairing: PairingPayload) {
        let profile: HostProfile
        if case .edit(let existing) = mode {
            profile = existing.applying(pairing)
        } else {
            var scannedProfile = HostProfile(pairing: pairing)
            if pairing.name == nil, !name.isEmpty { scannedProfile.name = name }
            profile = scannedProfile
        }
        onSave(profile, true)
    }

    // MARK: - Manual

    private var manualEntry: some View {
        Group {
            Section("Mac") {
                LabeledContent("Name") {
                    TextField("MacBook Pro", text: $name)
                        .multilineTextAlignment(.trailing)
                        .focused($focused, equals: .name)
                }
                LabeledContent("Host") {
                    TextField("100.67.189.40", text: $host)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .focused($focused, equals: .host)
                }
                LabeledContent("Port") {
                    TextField(String(WireProtocol.defaultPort), text: $port)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .focused($focused, equals: .port)
                }
                LabeledContent("Token") {
                    SecureField("Token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .focused($focused, equals: .token)
                }
            }

            if let error = validationError, touchedAny {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var touchedAny: Bool { !host.isEmpty || !token.isEmpty }

    private var validationError: String? {
        if host.trimmingCharacters(in: .whitespaces).isEmpty { return L.invalidHost }
        guard let port = UInt16(port.trimmingCharacters(in: .whitespaces)), port > 0 else {
            return L.invalidPort
        }
        if token.trimmingCharacters(in: .whitespaces).isEmpty { return L.invalidTokenField }
        return nil
    }

    private func commit(connect: Bool) {
        guard validationError == nil,
              let portValue = UInt16(port.trimmingCharacters(in: .whitespaces)) else { return }
        let host = host.trimmingCharacters(in: .whitespaces)
        let name = name.trimmingCharacters(in: .whitespaces)
        var profile: HostProfile
        if case .edit(let existing) = mode {
            profile = existing
        } else {
            profile = HostProfile(name: host, host: host, token: "")
        }
        profile.name = name.isEmpty ? host : name
        profile.host = host
        profile.port = portValue
        profile.token = token.trimmingCharacters(in: .whitespaces)
        onSave(profile, connect)
    }

}
