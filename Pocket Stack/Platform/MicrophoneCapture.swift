import AVFoundation
import AudioToolbox

enum MicrophoneCaptureError: LocalizedError {
    case permissionDenied
    case unavailable
    case cannotSelectDevice(OSStatus)

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Microphone permission is required. Enable it in System Settings > Privacy & Security > Microphone."
        case .unavailable: "The selected microphone is unavailable."
        case .cannotSelectDevice(let status): "Unable to select microphone (CoreAudio \(status))."
        }
    }
}

final class MicrophoneCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let onBuffer: @Sendable (AVAudioPCMBuffer) -> Void
    private let lock = NSLock()
    private var running = false

    init(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) { self.onBuffer = onBuffer }

    func start(deviceUID: String?) async throws {
        try await requestPermission()
        let input = engine.inputNode
        if let deviceID = AudioDeviceManager.deviceID(for: deviceUID) {
            guard let unit = input.audioUnit else { throw MicrophoneCaptureError.unavailable }
            var mutableID = deviceID
            let status = AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &mutableID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            guard status == noErr else { throw MicrophoneCaptureError.cannotSelectDevice(status) }
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw MicrophoneCaptureError.unavailable }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2_048, format: format) { [weak self] buffer, _ in
            self?.onBuffer(buffer)
        }
        try engine.start()
        lock.withLock { running = true }
    }

    func stop() {
        let wasRunning = lock.withLock { let value = running; running = false; return value }
        guard wasRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func requestPermission() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
            }
            if !granted { throw MicrophoneCaptureError.permissionDenied }
        default: throw MicrophoneCaptureError.permissionDenied
        }
    }
}
