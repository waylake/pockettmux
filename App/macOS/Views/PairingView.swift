import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import PocketTmuxAgent
import PocketTmuxKit
import SwiftUI

/// Pairing window built from a standard Form. The QR code is content and keeps
/// scanner-safe black-on-white colors; all surrounding chrome is native.
struct PairingView: View {
    @ObservedObject var controller: AgentController
    @AppStorage(MacSettings.Key.port) private var port = Int(WireProtocol.defaultPort)
    @State private var selectedAddress: HostInfo.Address.ID?
    @State private var revealToken = false
    @State private var copied: String?

    var body: some View {
        Form {
            Section {
                qr
                    .listRowBackground(Color.clear)
            } header: {
                Text("Pairing Code")
            }

            Section("Connection") {
                LabeledContent("Address") {
                    Picker("Address", selection: $selectedAddress) {
                        ForEach(controller.addresses) { address in
                            Text("\(address.ip) · \(address.label)").tag(Optional(address.id))
                        }
                    }
                    .labelsHidden()
                    .disabled(controller.addresses.isEmpty)
                }

                LabeledContent("Link") {
                    HStack(spacing: 8) {
                        Text(link)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        CopyButton(id: "link", text: link, copied: $copied)
                    }
                }

                LabeledContent("Token") {
                    HStack(spacing: 8) {
                        Text(revealToken ? controller.token : Format.masked(controller.token))
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .textSelection(.enabled)
                        Button(revealToken ? "Hide" : "Reveal") { revealToken.toggle() }
                        CopyButton(id: "token", text: controller.token, copied: $copied)
                    }
                }
            }

            Section {
                Text("On the iPhone, open PocketTmux, tap Add Mac, then Scan QR.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 540)
        .onAppear { controller.refreshAddresses() }
        .onChange(of: controller.addresses, initial: true) { _, addresses in
            if selectedAddress == nil || !addresses.contains(where: { $0.id == selectedAddress }) {
                selectedAddress = addresses.first?.id
            }
        }
    }

    @ViewBuilder private var qr: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.white)
            if let image = payload.flatMap({ QRCode.image($0.url.absoluteString) }) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .padding(16)
            } else {
                ContentUnavailableView("No Network Interface",
                                       systemImage: "wifi.slash",
                                       description: Text("Connect the Mac to a network and try again."))
            }
        }
        .frame(width: 250, height: 250)
        .frame(maxWidth: .infinity)
    }

    private var address: HostInfo.Address? {
        controller.addresses.first { $0.id == selectedAddress } ?? controller.addresses.first
    }

    private var payload: PairingPayload? {
        guard let address else { return nil }
        return PairingPayload(host: address.ip, port: UInt16(clamping: port), token: controller.token,
                              name: MacSettings.hostName)
    }

    private var link: String { payload?.url.absoluteString ?? "" }
}

/// Standard Copy button with brief confirmation.
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

/// CoreImage QR with scanner-safe contrast and nearest-neighbour scaling.
enum QRCode {
    private static let context = CIContext()

    static func image(_ string: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let code = filter.outputImage else { return nil }
        let tint = CIFilter.falseColor()
        tint.inputImage = code
        tint.color0 = CIColor(red: 0, green: 0, blue: 0)
        tint.color1 = CIColor(red: 1, green: 1, blue: 1)
        guard let output = tint.outputImage,
              let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
