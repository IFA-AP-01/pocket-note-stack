import AVFoundation
import Foundation
import Speech

@available(macOS 26.0, *)
struct AppleDictationEngine: DictationEngine {
    func start(localeIdentifier: String?, deviceUID: String?, audioSource: AudioSource) async throws -> any DictationSession {
        try await AppleDictationSession.create(localeIdentifier: localeIdentifier, deviceUID: deviceUID, audioSource: audioSource)
    }

    static func modelStatus(localeIdentifier: String) async -> AssetInventory.Status {
        let locale = await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeIdentifier))
        guard let locale else { return .unsupported }
        let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
        return await AssetInventory.status(forModules: [transcriber])
    }
}

@available(macOS 26.0, *)
final class AppleDictationSession: DictationSession, @unchecked Sendable {
    let events: AsyncThrowingStream<TranscriptEvent, Error>
    private let eventContinuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation
    private let inputContinuation: AsyncStream<AnalyzerInput>.Continuation
    private let microphone: MicrophoneCapture?
    private let screenCapture: ScreenAudioCapture?
    private let analyzer: SpeechAnalyzer
    private var analysisTask: Task<Void, Never>?
    private var resultTask: Task<Void, Never>?
    private let lock = NSLock()
    private var stopped = false

    private init(
        events: AsyncThrowingStream<TranscriptEvent, Error>,
        eventContinuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation,
        inputContinuation: AsyncStream<AnalyzerInput>.Continuation,
        microphone: MicrophoneCapture?,
        screenCapture: ScreenAudioCapture?,
        analyzer: SpeechAnalyzer
    ) {
        self.events = events
        self.eventContinuation = eventContinuation
        self.inputContinuation = inputContinuation
        self.microphone = microphone
        self.screenCapture = screenCapture
        self.analyzer = analyzer
    }

    static func create(localeIdentifier: String?, deviceUID: String?, audioSource: AudioSource) async throws -> AppleDictationSession {
        let requested = Locale(identifier: localeIdentifier ?? Locale.current.identifier)
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: requested) else {
            throw DictationError.unsupportedLocale(requested.identifier)
        }
        let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw DictationError.audioFormatUnavailable
        }
        let (inputs, inputContinuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let (events, eventContinuation) = AsyncThrowingStream.makeStream(of: TranscriptEvent.self)
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        var microphone: MicrophoneCapture?
        var screenCapture: ScreenAudioCapture?

        switch audioSource {
        case .microphone:
            let converter = AudioBufferConverter(targetFormat: format)
            let mic = MicrophoneCapture { buffer in
                guard let converted = converter.convert(buffer), converted.frameLength > 0 else {
                    return
                }
                inputContinuation.yield(AnalyzerInput(buffer: converted))
            }
            try await mic.start(deviceUID: deviceUID)
            microphone = mic

        case .screen:
            let converter = AudioBufferConverter(targetFormat: format)
            let screen = ScreenAudioCapture(onBuffer: { buffer in
                guard let converted = converter.convert(buffer), converted.frameLength > 0 else {
                    return
                }
                inputContinuation.yield(AnalyzerInput(buffer: converted))
            })
            try await screen.start()
            screenCapture = screen

        case .both:
            let micConverter = AudioBufferConverter(targetFormat: format)
            let screenConverter = AudioBufferConverter(targetFormat: format)
            let mixer = AppleAudioMixer(targetFormat: format)

            let screen = ScreenAudioCapture(onBuffer: { buffer in
                guard let converted = screenConverter.convert(buffer), converted.frameLength > 0 else { return }
                mixer.pushScreen(converted)
            })

            let mic = MicrophoneCapture { buffer in
                guard let converted = micConverter.convert(buffer), converted.frameLength > 0 else { return }
                let mixed = mixer.mixMic(converted)
                inputContinuation.yield(AnalyzerInput(buffer: mixed))
            }

            try await screen.start()
            try await mic.start(deviceUID: deviceUID)
            screenCapture = screen
            microphone = mic
        }

        let session = AppleDictationSession(
            events: events,
            eventContinuation: eventContinuation,
            inputContinuation: inputContinuation,
            microphone: microphone,
            screenCapture: screenCapture,
            analyzer: analyzer
        )
        session.resultTask = Task {
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    eventContinuation.yield(result.isFinal ? .final(text) : .interim(text))
                }
                eventContinuation.finish()
            } catch {
                eventContinuation.finish(throwing: error)
            }
        }
        session.analysisTask = Task {
            do {
                let end = try await analyzer.analyzeSequence(inputs)
                if let end { try await analyzer.finalizeAndFinish(through: end) }
                else { await analyzer.cancelAndFinishNow() }
            } catch {
                eventContinuation.finish(throwing: error)
            }
        }
        return session
    }

    func stop() async {
        guard lock.withLock({ if stopped { return false }; stopped = true; return true }) else { return }
        microphone?.stop()
        await screenCapture?.stop()
        inputContinuation.finish()
        await analysisTask?.value
        eventContinuation.finish()
    }

    func cancel() async {
        microphone?.stop()
        await screenCapture?.stop()
        inputContinuation.finish()
        await analyzer.cancelAndFinishNow()
        analysisTask?.cancel()
        resultTask?.cancel()
        eventContinuation.finish()
    }
}

final class AppleAudioMixer: @unchecked Sendable {
    private let lock = NSLock()
    private var screenSamplesInt16: [Int16] = []
    private var screenSamplesFloat: [Float] = []
    private let targetFormat: AVAudioFormat
    private let maxBufferedSamples: Int
    private let isFloat: Bool

    init(targetFormat: AVAudioFormat) {
        self.targetFormat = targetFormat
        self.maxBufferedSamples = Int(targetFormat.sampleRate)
        self.isFloat = targetFormat.commonFormat == .pcmFormatFloat32
    }

    func pushScreen(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }

            if isFloat, let channel = buffer.floatChannelData?[0] {
                screenSamplesFloat.reserveCapacity(screenSamplesFloat.count + count)
                for i in 0..<count { screenSamplesFloat.append(channel[i]) }
                if screenSamplesFloat.count > maxBufferedSamples {
                    screenSamplesFloat.removeFirst(screenSamplesFloat.count - maxBufferedSamples)
                }
            } else if let channel = buffer.int16ChannelData?[0] {
                screenSamplesInt16.reserveCapacity(screenSamplesInt16.count + count)
                for i in 0..<count { screenSamplesInt16.append(channel[i]) }
                if screenSamplesInt16.count > maxBufferedSamples {
                    screenSamplesInt16.removeFirst(screenSamplesInt16.count - maxBufferedSamples)
                }
            }
        }
    }

    func mixMic(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        lock.withLock {
            let micCount = Int(buffer.frameLength)
            guard micCount > 0 else { return buffer }
            guard let mixedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: buffer.frameCapacity) else { return buffer }
            mixedBuffer.frameLength = buffer.frameLength

            let channelCount = Int(targetFormat.channelCount)

            if isFloat {
                let availableScreen = min(screenSamplesFloat.count, micCount)
                for ch in 0..<channelCount {
                    guard let micPtr = buffer.floatChannelData?[ch],
                          let mixedPtr = mixedBuffer.floatChannelData?[ch] else { continue }
                    for i in 0..<availableScreen {
                        let sum = micPtr[i] + screenSamplesFloat[i]
                        mixedPtr[i] = max(-1.0, min(1.0, sum))
                    }
                    if availableScreen < micCount {
                        for i in availableScreen..<micCount {
                            mixedPtr[i] = micPtr[i]
                        }
                    }
                }
                if availableScreen > 0 {
                    screenSamplesFloat.removeFirst(availableScreen)
                }
            } else {
                let availableScreen = min(screenSamplesInt16.count, micCount)
                for ch in 0..<channelCount {
                    guard let micPtr = buffer.int16ChannelData?[ch],
                          let mixedPtr = mixedBuffer.int16ChannelData?[ch] else { continue }
                    for i in 0..<availableScreen {
                        let sum = Int32(micPtr[i]) + Int32(screenSamplesInt16[i])
                        let clamped = max(Int32(Int16.min), min(Int32(Int16.max), sum))
                        mixedPtr[i] = Int16(clamped)
                    }
                    if availableScreen < micCount {
                        for i in availableScreen..<micCount {
                            mixedPtr[i] = micPtr[i]
                        }
                    }
                }
                if availableScreen > 0 {
                    screenSamplesInt16.removeFirst(availableScreen)
                }
            }

            return mixedBuffer
        }
    }
}

enum DictationError: LocalizedError {
    case unsupportedLocale(String)
    case audioFormatUnavailable
    case appleOnDeviceUnavailable
    case missingAPIKey
    case invalidServerResponse
    case timedOut
    case screenCapturePermissionDenied

    var errorDescription: String? {
        switch self {
        case .unsupportedLocale(let locale): "Apple on-device dictation does not support \(locale)."
        case .audioFormatUnavailable: "No compatible microphone format is available."
        case .appleOnDeviceUnavailable: "Apple on-device dictation requires macOS 26 or later."
        case .missingAPIKey: "Add a Gemini API key in Settings > Speech."
        case .invalidServerResponse: "Gemini returned an invalid response."
        case .timedOut: "The transcription service timed out."
        case .screenCapturePermissionDenied: "Screen Recording permission is required. Enable it in System Settings > Privacy & Security > Screen Recording."
        }
    }
}
