import AVFoundation
import Foundation
import Speech

struct AppleDictationEngine: DictationEngine {
    func start(localeIdentifier: String?, deviceUID: String?) async throws -> any DictationSession {
        try await AppleDictationSession.create(localeIdentifier: localeIdentifier, deviceUID: deviceUID)
    }

    static func modelStatus(localeIdentifier: String) async -> AssetInventory.Status {
        let locale = await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeIdentifier))
        guard let locale else { return .unsupported }
        let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
        return await AssetInventory.status(forModules: [transcriber])
    }
}

final class AppleDictationSession: DictationSession, @unchecked Sendable {
    let events: AsyncThrowingStream<TranscriptEvent, Error>
    private let eventContinuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation
    private let inputContinuation: AsyncStream<AnalyzerInput>.Continuation
    private let microphone: MicrophoneCapture
    private let analyzer: SpeechAnalyzer
    private var analysisTask: Task<Void, Never>?
    private var resultTask: Task<Void, Never>?
    private let lock = NSLock()
    private var stopped = false

    private init(
        events: AsyncThrowingStream<TranscriptEvent, Error>,
        eventContinuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation,
        inputContinuation: AsyncStream<AnalyzerInput>.Continuation,
        microphone: MicrophoneCapture,
        analyzer: SpeechAnalyzer
    ) {
        self.events = events
        self.eventContinuation = eventContinuation
        self.inputContinuation = inputContinuation
        self.microphone = microphone
        self.analyzer = analyzer
    }

    static func create(localeIdentifier: String?, deviceUID: String?) async throws -> AppleDictationSession {
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
        let converter = AudioBufferConverter(targetFormat: format)
        let (inputs, inputContinuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let (events, eventContinuation) = AsyncThrowingStream.makeStream(of: TranscriptEvent.self)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let microphone = MicrophoneCapture { buffer in
            guard let converted = converter.convert(buffer) else { return }
            inputContinuation.yield(AnalyzerInput(buffer: converted))
        }
        let session = AppleDictationSession(
            events: events,
            eventContinuation: eventContinuation,
            inputContinuation: inputContinuation,
            microphone: microphone,
            analyzer: analyzer
        )
        session.resultTask = Task {
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    eventContinuation.yield(result.isFinal ? .final(text) : .interim(text))
                }
                eventContinuation.finish()
            } catch { eventContinuation.finish(throwing: error) }
        }
        session.analysisTask = Task {
            do {
                let end = try await analyzer.analyzeSequence(inputs)
                if let end { try await analyzer.finalizeAndFinish(through: end) }
                else { await analyzer.cancelAndFinishNow() }
            } catch { eventContinuation.finish(throwing: error) }
        }
        try await microphone.start(deviceUID: deviceUID)
        return session
    }

    func stop() async {
        guard lock.withLock({ if stopped { return false }; stopped = true; return true }) else { return }
        microphone.stop()
        inputContinuation.finish()
        await analysisTask?.value
        eventContinuation.finish()
    }

    func cancel() async {
        microphone.stop()
        inputContinuation.finish()
        await analyzer.cancelAndFinishNow()
        analysisTask?.cancel()
        resultTask?.cancel()
        eventContinuation.finish()
    }
}

enum DictationError: LocalizedError {
    case unsupportedLocale(String)
    case audioFormatUnavailable
    case missingAPIKey
    case invalidServerResponse
    case timedOut

    var errorDescription: String? {
        switch self {
        case .unsupportedLocale(let locale): "Apple on-device dictation does not support \(locale)."
        case .audioFormatUnavailable: "No compatible microphone format is available."
        case .missingAPIKey: "Add a Gemini API key in Settings > Speech."
        case .invalidServerResponse: "Gemini returned an invalid response."
        case .timedOut: "The transcription service timed out."
        }
    }
}
