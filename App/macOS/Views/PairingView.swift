import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import PocketTmuxAgent
import PocketTmuxKit
import SwiftUI

/// "Pair iPhone" window: QR + address picker + link + token. 420×560.
struct PairingView: View {
    @ObservedObject var controller: AgentController
    @AppStorage(MacSettings.Key.port) private var port = Int(WireProtocol.defaultPort)
    @State private var selectedAddress: HostInfo.Address.ID?
    @State private var revealToken = false
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            qr
            addressPicker
            linkRow
            tokenRow
            Spacer(minLength: 0)
            Text("On the iPhone: PocketTmux → Add Mac → Scan QR")
                .font(MacTheme.mono(11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(width: 420, height: 560)
        .onAppear { controller.refreshAddresses() }
        .onChange(of: controller.addresses, initial: true) { _, addresses in
            if selectedAddress == nil || !addresses.contains(where: { $0.id == selectedAddress }) {
                selectedAddress = addresses.first?.id
            }
        }
    }

    // MARK: - Pieces

    private var address: HostInfo.Address? {
        controller.addresses.first { $0.id == selectedAddress } ?? controller.addresses.first
    }

    private var payload: PairingPayload? {
        guard let address else { return nil }
        return PairingPayload(host: address.ip, port: UInt16(clamping: port), token: controller.token,
                              name: MacSettings.hostName)
    }

    private var link: String { payload?.url.absoluteString ?? "" }

    @ViewBuilder private var qr: some View {
        ZStack {
            RoundedRectangle(cornerRadius: MacTheme.radius)
                .fill(MacTheme.washi)
            if let image = payload.flatMap({ QRCode.image($0.url.absoluteString) }) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .padding(16)
            } else {
                Text("No network interface is up")
                    .font(MacTheme.mono(12))
                    .foregroundStyle(MacTheme.sumi)
            }
        }
        .frame(width: 260, height: 260)
        .frame(maxWidth: .infinity)
    }

    private var addressPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel("ADDRESS")
            Picker("", selection: $selectedAddress) {
                ForEach(controller.addresses) { address in
                    Text("\(address.ip)  ·  \(address.label)")
                        .font(MacTheme.mono(12))
                        .tag(Optional(address.id))
                }
            }
            .labelsHidden()
            .disabled(controller.addresses.isEmpty)
        }
    }

    private var linkRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel("LINK")
            HStack(spacing: 8) {
                Text(link)
                    .font(MacTheme.mono(11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
                CopyButton(id: "link", text: link, copied: $copied)
            }
        }
    }

    private var tokenRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel("TOKEN")
            HStack(spacing: 8) {
                Text(revealToken ? controller.token : Format.masked(controller.token))
                    .font(MacTheme.mono(11))
                    .lineLimit(1)
                    .textSelection(.enabled)
                Spacer()
                Button(revealToken ? "Hide" : "Reveal") { revealToken.toggle() }
                CopyButton(id: "token", text: controller.token, copied: $copied)
            }
        }
    }
}

/// "Copy" that reads "Copied" for a moment after a click.
struct CopyButton: View {
    let id: String
    let text: String
    @Binding var copied: String?

    var body: some View {
        Button(copied == id ? "Copied" : "Copy") {
            AgentController.copy(text)
            copied = id
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                if copied == id { copied = nil }
            }
        }
        .disabled(text.isEmpty)
    }
}

/// CoreImage QR, sumi modules on washi, left unscaled so SwiftUI's
/// nearest-neighbour interpolation keeps the edges crisp.
enum QRCode {
    private static let context = CIContext()

    static func image(_ string: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let code = filter.outputImage else { return nil }
        let tint = CIFilter.falseColor()
        tint.inputImage = code
        tint.color0 = CIColor(red: 0.043, green: 0.051, blue: 0.067)     // #0B0D11
        tint.color1 = CIColor(red: 0.894, green: 0.878, blue: 0.831)     // #E4E0D4
        guard let output = tint.outputImage,
              let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
