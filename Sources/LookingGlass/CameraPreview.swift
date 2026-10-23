import AVFoundation
import SwiftUI

/// Live camera layer with zoom, rotation and mirroring applied to the layer itself.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let aspect: CGFloat
    let mirrored: Bool
    let zoom: Double
    let rotation: Double
    let isCircle: Bool

    func makeNSView(context: Context) -> PreviewHostView { PreviewHostView(session: session) }

    func updateNSView(_ view: PreviewHostView, context: Context) {
        view.aspect = aspect
        view.mirrored = mirrored
        view.zoom = zoom
        view.rotation = rotation
        view.isCircle = isCircle
        view.needsLayout = true
        view.applyMirroring()
    }
}

final class PreviewHostView: NSView {
    private let previewLayer: AVCaptureVideoPreviewLayer
    var aspect: CGFloat = 16.0 / 9.0
    var mirrored = true
    var zoom = 1.0
    var rotation = 0.0
    var isCircle = false

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.cgColor
        previewLayer.videoGravity = .resizeAspect   // the layer is sized to the video's own aspect
        layer?.addSublayer(previewLayer)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionStarted),
                                               name: AVCaptureSession.didStartRunningNotification, object: session)
    }

    required init?(coder: NSCoder) { fatalError() }

    // Lets the pop-out window be dragged by grabbing the video.
    override var mouseDownCanMoveWindow: Bool { true }

    @objc private func sessionStarted() { DispatchQueue.main.async { self.applyMirroring() } }

    func applyMirroring() {
        guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = mirrored
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        guard w > 0, h > 0 else { return }

        // Aspect-fill the video into the view...
        let (vw, vh): (CGFloat, CGFloat) = aspect >= w / h ? (h * aspect, h) : (w, w / aspect)
        // ...then rotate/zoom about the centre, with just enough extra scale that no empty corners show.
        let theta = -CGFloat(rotation) * .pi / 180   // positive = clockwise
        let cover = isCircle ? 1 : PhotoComposer.coverScale(viewW: w, viewH: h, videoW: vw, videoH: vh, theta: theta)
        let scale = CGFloat(zoom) * cover

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.transform = CATransform3DIdentity
        previewLayer.frame = CGRect(x: bounds.midX - vw / 2, y: bounds.midY - vh / 2, width: vw, height: vh)
        var t = CATransform3DMakeRotation(theta, 0, 0, 1)
        t = CATransform3DScale(t, scale, scale, 1)
        previewLayer.transform = t
        CATransaction.commit()
        applyMirroring()
    }
}
