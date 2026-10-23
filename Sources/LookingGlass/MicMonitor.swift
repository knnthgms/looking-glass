import AVFoundation
import Combine

/// Live input level for the "mic check" meter. Runs only while the mirror is visible.
final class MicMonitor: ObservableObject {
    static let shared = MicMonitor()

    @Published private(set) var level: Float = 0           // 0...1
    @Published private(set) var authorization = AVCaptureDevice.authorizationStatus(for: .audio)

    private let engine = AVAudioEngine()
    private var running = false
    private var smoothed: Float = 0

    func start() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        authorization = status
        switch status {
        case .authorized: begin()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    self.authorization = AVCaptureDevice.authorizationStatus(for: .audio)
                    if granted { self.begin() }
                }
            }
        default: break
        }
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        smoothed = 0
        level = 0
    }

    private func begin() {
        guard !running else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        do {
            try engine.start()
            running = true
        } catch {
            input.removeTap(onBus: 0)
            NSLog("LookingGlass: mic engine failed: \(error.localizedDescription)")
        }
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += samples[i] * samples[i] }
        let rms = (sum / Float(max(n, 1))).squareRoot()
        let db = 20 * log10(max(rms, 1e-6))
        let normalized = max(0, min(1, (db + 60) / 60))
        DispatchQueue.main.async {
            self.smoothed = max(normalized, self.smoothed * 0.82)   // fast attack, gentle release
            self.level = self.smoothed
        }
    }
}
