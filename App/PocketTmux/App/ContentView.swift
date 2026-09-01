import SwiftUI

/// PocketTmux main screen.
///
/// v0.1 skeleton: connection bar + placeholder terminal surface.
/// P1 integration points are marked with `// P1:` comments:
///  - embed a `TerminalView` (SwiftTerm) in the terminal area
///  - wire the `Transport` (WebSocket) in the session store
struct ContentView: View {
    @State private var host = ""
    @State private var port = "7681"

    var body: some View {
        VStack(spacing: 0) {
            connectionBar
            Divider()
            terminalPlaceholder
        }
        .background(Color.black.ignoresSafeArea())
    }

    private var connectionBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            TextField("host", text: $host)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            TextField("port", text: $port)
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            // P1: connect button → Transport.connect(host:port:)
        }
        .padding()
    }

    private var terminalPlaceholder: some View {
        // P1: replace with the SwiftTerm TerminalView (UIViewRepresentable)
        ScrollView {
            Text("Connecting to \(host.isEmpty ? "…" : host):\(port) …\n\n(PocketTmux 0.1 — planning & skeleton)")
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding()
        }
    }
}

#Preview {
    ContentView()
}
