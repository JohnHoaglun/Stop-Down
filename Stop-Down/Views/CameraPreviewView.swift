import AVFoundation
import SwiftUI
import UIKit

/// The live camera preview behind the meter UI (spec §4.7).
///
/// `AVCaptureVideoPreviewLayer` is UIKit-only, so this is the single
/// `UIViewRepresentable` wrapper the app is allowed to use for the preview.
/// Aspect-fill gravity keeps the preview full-screen; the same fill crop is
/// what `SpotPointConverter` models for screen→capture math (spec FR-3).
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewLayerHostView {
        let view = PreviewLayerHostView()
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewLayerHostView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }
}

/// A plain host view whose backing layer is the preview layer.
final class PreviewLayerHostView: UIView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}
