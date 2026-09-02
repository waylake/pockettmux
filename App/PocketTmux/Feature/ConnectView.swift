import SwiftUI

/// Screen 1 — Connect. Host / port / token with Keychain persistence.
/// First-run flow reads the agent token once (paste) and keeps it in Keychain.
struct ConnectView: View {
    @EnvironmentObject private var client: AgentClient
    @Binding var path: [Route]

    @State private var host = ""
    @State private var port = "7682"
    @State private var token = ""
    @State private var didAutoConnect = false
    @State private var showScanner = false
    @State private var cameraDenied = false

    private var canConnect: Bool {
        !host.isEmpty && !token.isEmpty && client.status != .connecting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            form
            Spacer()
            connectButton
        }
        .padding(.horizontal, 20)
        .background(Theme.bg.ignoresSafeArea())
        .onAppear { autofill() }
        .onChange(of: client.status) { new in
            if new == .connected, !didAutoConnect {
                didAutoConnect = true
                path.append(.sessions)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PocketTmux")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.paper)
            Text("POCKETTMUX · YOUR MAC TERMINAL IN YOUR POCKET")
                .font(Theme.mono(10))
                .tracking(1.2)
                .foregroundStyle(Theme.muted)
        }
        .padding(.top, 56)
        .padding(.bottom, 36)
    }

    private var form: some View {
        VStack(spacing: 16) {
            field(title: "HOST", text: $host, placeholder: "100.67.189.40")
            HStack(spacing: 12) {
                field(title: "PORT", text: $port, placeholder: "7682", width: 110, keyboard: .numberPad)
                field(title: "TOKEN", text: $token, placeholder: "••••••••")
            }
            statusRow
            scanRow
        }
    }

    private func field(title: String, text: Binding<String>, placeholder: String,
                       width: CGFloat? = nil, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.mono(9))
                .tracking(1.5)
                .foregroundStyle(Theme.muted)
            HStack(spacing: 8) {
                TextField(placeholder, text: text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(keyboard)
                    .font(Theme.mono(15))
                    .foregroundStyle(Theme.paper)
                if title == "HOST" {
                    Button { host = "100.67.189.40" } label: {
                        Image(systemName: "location")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.indigo)
                }
            }
            .padding(12)
            .background(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.surface2, lineWidth: 1))
        }
        .frame(width: width)
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle().fill(statusColor).frame(width: 7, height: 7)
            Text(statusText)
                .font(Theme.mono(11))
                .foregroundStyle(statusColor)
            Spacer()
            if let err = client.lastError, client.status == .reconnecting {
                Text(L.retrying)
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.yamabuki)
                Text(err).lineLimit(1).font(Theme.mono(9)).foregroundStyle(Theme.muted)
            }
        }
        .padding(.top, 8)
    }

    private var scanRow: some View {
        HStack(spacing: 8) {
            Button {
                showScanner = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "qrcode.viewfinder")
                    Text("Scan pairing QR")
                        .font(Theme.mono(11, .semibold))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.indigo)
            Spacer()
        }
        .padding(.top, 4)
        .sheet(isPresented: $showScanner) {
            scannerSheet
        }
    }

    private var scannerSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SCAN PAIRING QR")
                    .font(Theme.mono(12, .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.paper)
                Spacer()
                Button {
                    showScanner = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Theme.surface)

            QRScannerView(onDenied: { cameraDenied = true }) { payload in
                apply(payload: payload)
            }
            .onAppear { cameraDenied = false }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Theme.vermilion, lineWidth: 2)
                    .frame(width: 220, height: 220)
                    .opacity(0.9)
            }
            .background(Theme.bg)

            Text(cameraDenied
                 ? "Camera access is off — enable it in Settings → PocketTmux, or type host/token manually."
                 : "Run `scripts/pair.sh` on your Mac and point the camera at the QR.")
                .font(Theme.mono(10))
                .foregroundStyle(cameraDenied ? Theme.yamabuki : Theme.muted)
                .padding(12)
                .background(Theme.surface)
        }
        .background(Theme.bg)
    }

    private func apply(payload: String) {
        guard let comps = URLComponents(string: payload),
              comps.scheme == "pockettmux",
              let q = comps.queryItems else { return }
        let get = { (k: String) -> String? in q.first(where: { $0.name == k })?.value }
        guard let h = get("host"), let t = get("token") else { return }
        host = h
        port = get("port") ?? "7682"
        token = t
        showScanner = false
        Task { await client.connect(CachedProfile(host: h, port: Int(get("port") ?? "7682") ?? 7682, token: t, lastSession: nil)) }
    }

    private var statusColor: Color {
        switch client.status {
        case .connected: return Theme.moegi
        case .connecting, .reconnecting: return Theme.yamabuki
        case .idle: return Theme.muted
        }
    }

    private var statusText: String {
        switch client.status {
        case .connected: return L.connected
        case .connecting: return L.connecting
        case .reconnecting: return L.reconnecting
        case .idle: return L.disconnected
        }
    }

    private var connectButton: some View {
        Button {
            Task { await client.connect(CachedProfile(host: host, port: Int(port) ?? 7682, token: token, lastSession: nil)) }
        } label: {
            HStack {
                Spacer()
                Text(canConnect ? L.connect : L.connect)
                    .font(Theme.mono(15, .semibold))
                    .tracking(2)
                Spacer()
            }
            .padding(.vertical, 15)
            .background(canConnect ? Theme.vermilion : Theme.surface2)
            .foregroundStyle(canConnect ? .white : Theme.muted)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(!canConnect)
        .padding(.bottom, 24)
    }

    private func autofill() {
        guard !didAutoConnect else { return }
        if let cached = Keychain.load() {
            host = cached.host
            port = String(cached.port)
            token = cached.token
            // One-tap resume: previously connected → reconnect silently.
            Task { await client.connect(cached) }
        }
    }
}
