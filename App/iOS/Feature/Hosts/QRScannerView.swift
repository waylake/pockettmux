import SwiftUI
import AVFoundation

/// Camera view that scans the pairing QR shown by PocketTmux on the Mac.
/// Payload format: `pockettmux://pair?host=…&port=7682&token=…&name=…`
///
/// Defensive by design:
///  - permission is requested explicitly; a denial shows a hint instead of a
///    black camera (and never crashes)
///  - the capture session is stopped *before* the scan callback fires, so the
///    sheet can dismiss without tearing down a live session
///  - the metadata delegate runs on the main queue (AVFoundation's standard
///    contract for UI-bound previews)
struct QRScannerView: UIViewRepresentable {
    var onDenied: (() -> Void)?
    var onFound: (String) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.onFound = onFound
        view.onDenied = onDenied
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    static func dismantleUIView(_ uiView: PreviewView, coordinator: ()) {
        uiView.stopSession()
    }

    final class PreviewView: UIView, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
        var onFound: ((String) -> Void)?
        var onDenied: (() -> Void)?

        private var session: AVCaptureSession?
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private var fired = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, session == nil else { return }
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                startSession()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    DispatchQueue.main.async {
                        if granted { self?.startSession() } else { self?.onDenied?() }
                    }
                }
            default:
                onDenied?()
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer?.frame = bounds
        }

        private func startSession() {
            let session = AVCaptureSession()
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { onDenied?(); return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { onDenied?(); return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = bounds
            self.layer.addSublayer(layer)
            previewLayer = layer
            session.startRunning()
            self.session = session
        }

        func stopSession() {
            session?.stopRunning()
            previewLayer?.removeFromSuperlayer()
            previewLayer = nil
            session = nil
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !fired,
                  let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = obj.stringValue,
                  value.hasPrefix("pockettmux://") else { return }
            fired = true
            stopSession()   // stop before notifying: the sheet may dismiss us
            onFound?(value)
        }
    }
}
