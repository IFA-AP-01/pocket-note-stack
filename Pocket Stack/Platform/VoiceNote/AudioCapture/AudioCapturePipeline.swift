import AVFoundation

actor AudioCapturePipeline {
    private let request: DictationRequest
    private let targetFormat: AVAudioFormat
    private let onBuffer: @Sendable (AVAudioPCMBuffer) -> Void
    private let onLevel: (@Sendable (Float) -> Void)?

    private var microphone: MicrophoneCapture?
    private var screenCapture: ScreenAudioCapture?

    init(
        request: DictationRequest,
        targetFormat: AVAudioFormat,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onLevel: (@Sendable (Float) -> Void)? = nil
    ) {
        self.request = request
        self.targetFormat = targetFormat
        self.onBuffer = onBuffer
        self.onLevel = onLevel
    }

    func start() async throws {
        let microphoneConverter = AudioFormatConverter(targetFormat: targetFormat)
        let screenConverter = AudioFormatConverter(targetFormat: targetFormat)
        let mixer = AudioBufferMixer(targetFormat: targetFormat)
        let onBuffer = self.onBuffer
        let onLevel = self.onLevel

        @Sendable func emit(_ buffer: AVAudioPCMBuffer) {
            onLevel?(AudioLevelMeter.normalizedRMS(of: buffer))
            onBuffer(buffer)
        }

        switch request.audioSource {
        case .microphone:
            let capture = MicrophoneCapture { buffer in
                guard let converted = microphoneConverter.convert(buffer), converted.frameLength > 0 else { return }
                emit(converted)
            }
            try await capture.start(deviceUID: request.deviceUID)
            microphone = capture

        case .screen:
            let capture = ScreenAudioCapture(onBuffer: { buffer in
                guard let converted = screenConverter.convert(buffer), converted.frameLength > 0 else { return }
                emit(converted)
            })
            try await capture.start()
            screenCapture = capture

        case .both:
            let screen = ScreenAudioCapture(onBuffer: { buffer in
                guard let converted = screenConverter.convert(buffer), converted.frameLength > 0 else { return }
                mixer.pushScreen(converted)
            })
            let microphone = MicrophoneCapture { buffer in
                guard let converted = microphoneConverter.convert(buffer), converted.frameLength > 0 else { return }
                emit(mixer.mixMicrophone(converted))
            }
            try await screen.start()
            try await microphone.start(deviceUID: request.deviceUID)
            screenCapture = screen
            self.microphone = microphone
        }
    }

    func stop() async {
        microphone?.stop()
        microphone = nil
        await screenCapture?.stop()
        screenCapture = nil
        onLevel?(0)
    }
}
