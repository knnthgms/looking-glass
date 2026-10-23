import AVFoundation
import Combine

/// Owns the single capture session. Views and controllers `acquire()` it while visible and
/// `release()` it afterwards; the camera (and its green light) shuts off shortly after the last release.
final class CameraModel: NSObject, ObservableObject {
    static let shared = CameraModel()

    @Published private(set) var authorization = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var devices: [AVCaptureDevice] = []
    @Published private(set) var isRunning = false
    @Published private(set) var aspect: CGFloat = 16.0 / 9.0

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "LookingGlass.camera")
    private var holders = 0                       // main thread only
    private var stopWork: DispatchWorkItem?       // main thread only
    private var currentID: String?                // session queue only
    private var inflight: [ObjectIdentifier: PhotoDelegate] = [:]   // session queue only

    override init() {
        super.init()
        refreshDevices()
        let nc = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refreshDevices() }
        }
        for name in [AVCaptureSession.didStartRunningNotification, AVCaptureSession.didStopRunningNotification] {
            nc.addObserver(forName: name, object: session, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.isRunning = self.session.isRunning
            }
        }
    }

    // MARK: Lifecycle

    func acquire() {
        holders += 1
        stopWork?.cancel()
        stopWork = nil
        requestAccess { [weak self] granted in
            guard let self, granted, self.holders > 0 else { return }
            self.queue.async {
                self.configureIfNeeded()
                if !self.session.isRunning { self.session.startRunning() }
            }
        }
    }

    func release() {
        holders = max(0, holders - 1)
        guard holders == 0 else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.holders == 0 else { return }
            self.queue.async { if self.session.isRunning { self.session.stopRunning() } }
        }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func requestAccess(_ done: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        authorization = status
        switch status {
        case .authorized: done(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.authorization = AVCaptureDevice.authorizationStatus(for: .video)
                    done(granted)
                }
            }
        default: done(false)
        }
    }

    // MARK: Devices

    func refreshDevices() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
            mediaType: .video, position: .unspecified)
        devices = discovery.devices
    }

    /// Called when the camera preference changes.
    func applyPreferredDevice() {
        guard holders > 0 else { return }
        queue.async { self.configureIfNeeded() }
    }

    private func pickDevice() -> AVCaptureDevice? {
        let id = UserDefaults.standard.string(forKey: Key.cameraID) ?? ""
        if !id.isEmpty, let d = AVCaptureDevice(uniqueID: id) { return d }
        return AVCaptureDevice.default(for: .video)
            ?? AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external],
                                                mediaType: .video, position: .unspecified).devices.first
    }

    /// Session queue only.
    private func configureIfNeeded() {
        guard let device = pickDevice(), device.uniqueID != currentID else { return }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            if session.canAddInput(input) { session.addInput(input) }
            if session.canSetSessionPreset(.photo) { session.sessionPreset = .photo }
            if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
            session.commitConfiguration()
            currentID = device.uniqueID
            let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
            DispatchQueue.main.async { self.aspect = CGFloat(dims.width) / CGFloat(max(dims.height, 1)) }
        } catch {
            NSLog("LookingGlass: could not open camera: \(error.localizedDescription)")
        }
    }

    // MARK: Photos

    /// Captures a still. The result is the raw camera frame, un-mirrored and un-cropped.
    func capturePhoto() async -> CGImage? {
        await withCheckedContinuation { (cont: CheckedContinuation<CGImage?, Never>) in
            queue.async {
                guard self.session.isRunning, self.session.outputs.contains(self.photoOutput) else {
                    cont.resume(returning: nil)
                    return
                }
                var delegate: PhotoDelegate!
                delegate = PhotoDelegate { image in
                    cont.resume(returning: image)
                    self.queue.async { self.inflight[ObjectIdentifier(delegate)] = nil }
                }
                self.inflight[ObjectIdentifier(delegate)] = delegate
                self.photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: delegate)
            }
        }
    }
}

private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (CGImage?) -> Void
    init(completion: @escaping (CGImage?) -> Void) { self.completion = completion }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            completion(nil)
            return
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // honour EXIF orientation
            kCGImageSourceThumbnailMaxPixelSize: 4000,
        ]
        completion(CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary))
    }
}
