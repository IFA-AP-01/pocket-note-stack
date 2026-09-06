import Foundation
import AVFoundation

actor CompositeAudioCapture {
    private let audioSource: AudioSource
    private let onChunk: @Sendable (Data) -> Void

    private var micCapture: MicrophoneCapture?
    private var screenCapture: ScreenAudioCapture?
    private var encoder: PCM16StreamEncoder
    private let mixer = PCM16Mixer()

    init(audioSource: AudioSource, onChunk: @escaping @Sendable (Data) -> Void) {
        self.audioSource = audioSource
        self.onChunk = onChunk
        self.encoder = PCM16StreamEncoder()
    }

    func start(deviceUID: String?) async throws {
        switch audioSource {
        case .microphone:
            try await startMicrophone(deviceUID: deviceUID)
        case .screen:
            try await startScreenCapture()
        case .both:
            try await startMicrophone(deviceUID: deviceUID)
            try await startScreenCapture()
        }
    }

    func stop() async {
        micCapture?.stop()
        micCapture = nil
        await screenCapture?.stop()
        screenCapture = nil
    }

    private func startMicrophone(deviceUID: String?) async throws {
        let encoder = self.encoder
        let audioSource = self.audioSource
        let mixer = self.mixer
        let onChunk = self.onChunk
        let capture = MicrophoneCapture { buffer in
            let chunks = encoder.encode(buffer)
            if audioSource == .both {
                for chunk in chunks {
                    if let mixed = mixer.pushMic(chunk) { onChunk(mixed) }
                }
            } else {
                for chunk in chunks { onChunk(chunk) }
            }
        }
        try await capture.start(deviceUID: deviceUID)
        self.micCapture = capture
    }

    private func startScreenCapture() async throws {
        let audioSource = self.audioSource
        let mixer = self.mixer
        let onChunk = self.onChunk
        let capture = ScreenAudioCapture(onAudioChunk: { chunk in
            if audioSource == .both {
                mixer.pushScreen(chunk)
            } else {
                onChunk(chunk)
            }
        }, onStatus: { status in
            print("Screen Capture Status: \(status)")
        })
        try await capture.start()
        self.screenCapture = capture
    }
}

final class PCM16Mixer: @unchecked Sendable {
    private let lock = NSLock()
    private var micBuffer = Data()
    private var screenBuffer = Data()
    private let chunkSize = 3200 // 100ms at 16kHz 16-bit mono

    func pushMic(_ data: Data) -> Data? {
        lock.withLock {
            micBuffer.append(data)
            guard micBuffer.count >= chunkSize else { return nil }
            return mixNextChunk()
        }
    }

    func pushScreen(_ data: Data) {
        lock.withLock {
            screenBuffer.append(data)
            let maxScreenBuffer = chunkSize * 10
            if screenBuffer.count > maxScreenBuffer {
                screenBuffer.removeFirst(screenBuffer.count - maxScreenBuffer)
            }
        }
    }

    private func mixNextChunk() -> Data {
        guard micBuffer.count >= chunkSize else { return Data() }

        let micChunk = micBuffer.prefix(chunkSize)
        micBuffer.removeFirst(chunkSize)

        let screenChunkSize = min(screenBuffer.count, chunkSize)
        let screenChunk = screenBuffer.prefix(screenChunkSize)
        if screenChunkSize > 0 {
            screenBuffer.removeFirst(screenChunkSize)
        }

        var mixedData = Data(count: chunkSize)
        for i in 0..<(chunkSize / 2) {
            let micSample = micChunk.withUnsafeBytes { $0.load(fromByteOffset: i * 2, as: Int16.self) }
            let screenSample: Int16
            if i * 2 + 1 < screenChunkSize {
                screenSample = screenChunk.withUnsafeBytes { $0.load(fromByteOffset: i * 2, as: Int16.self) }
            } else {
                screenSample = 0
            }

            // Simple sum with saturation
            let sum = Int32(micSample) + Int32(screenSample)
            let clamped = max(Int32(Int16.min), min(Int32(Int16.max), sum))
            let result = Int16(clamped)

            mixedData.withUnsafeMutableBytes { $0.storeBytes(of: result, toByteOffset: i * 2, as: Int16.self) }
        }
        return mixedData
    }
}
