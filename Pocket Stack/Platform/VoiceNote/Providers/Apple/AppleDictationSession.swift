import AVFoundation
import CoreMedia
import Foundation
import Speech

@available(macOS 26.0, *)
final class AppleDictationSession: DictationSession, @unchecked Sendable {
    let events: AsyncThrowingStream<TranscriptEvent, Error>
    let audioLevels: AsyncStream<Float>?

    private let eventContinuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation
    private let inputContinuation: AsyncStream<AnalyzerInput>.Continuation
    private let audioLevelContinuation: AsyncStream<Float>.Continuation
    private let capture: AudioCapturePipeline
    private let analyzer: SpeechAnalyzer
    private var analysisTask: Task<Void, Never>?
    private var resultTask: Task<Void, Never>?
    private let lock = NSLock()
    private var stopped = false

    private init(
        events: AsyncThrowingStream<TranscriptEvent, Error>,
        eventContinuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation,
        inputContinuation: AsyncStream<AnalyzerInput>.Continuation,
        audioLevels: AsyncStream<Float>,
        audioLevelContinuation: AsyncStream<Float>.Continuation,
        capture: AudioCapturePipeline,
        analyzer: SpeechAnalyzer
    ) {
        self.events = events
        self.eventContinuation = eventContinuation
        self.inputContinuation = inputContinuation
        self.audioLevels = audioLevels
        self.audioLevelContinuation = audioLevelContinuation
        self.capture = capture
        self.analyzer = analyzer
    }

    static func create(request: DictationRequest) async throws -> AppleDictationSession {
        let requestedLocale = Locale(identifier: request.localeIdentifier ?? Locale.current.identifier)
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            throw DictationError.unsupportedLocale(requestedLocale.identifier)
        }
        let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installation.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw DictationError.audioFormatUnavailable
        }

        let (inputs, inputContinuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let (events, eventContinuation) = AsyncThrowingStream.makeStream(of: TranscriptEvent.self)
        let (levels, levelContinuation) = AsyncStream.makeStream(of: Float.self)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let capture = AudioCapturePipeline(
            request: request,
            targetFormat: format,
            onBuffer: { buffer in inputContinuation.yield(AnalyzerInput(buffer: buffer)) },
            onLevel: { levelContinuation.yield($0) }
        )

        let session = AppleDictationSession(
            events: events,
            eventContinuation: eventContinuation,
            inputContinuation: inputContinuation,
            audioLevels: levels,
            audioLevelContinuation: levelContinuation,
            capture: capture,
            analyzer: analyzer
        )
        try await capture.start()
        session.observeResults(from: transcriber)
        session.analyze(inputs)
        return session
    }

    private func observeResults(from transcriber: DictationTranscriber) {
        resultTask = Task {
            var pendingVolatileRange: CMTimeRange?
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if let pendingVolatileRange,
                       CMTimeCompare(result.range.start, pendingVolatileRange.end) >= 0 {
                        eventContinuation.yield(.promoteInterim)
                    }
                    if result.isFinal {
                        eventContinuation.yield(.final(text))
                        pendingVolatileRange = nil
                    } else {
                        eventContinuation.yield(.interim(text))
                        pendingVolatileRange = result.range
                    }
                }
                eventContinuation.finish()
            } catch {
                eventContinuation.finish(throwing: error)
            }
        }
    }

    private func analyze(_ inputs: AsyncStream<AnalyzerInput>) {
        analysisTask = Task {
            do {
                let end = try await analyzer.analyzeSequence(inputs)
                if let end {
                    try await analyzer.finalizeAndFinish(through: end)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
            } catch {
                eventContinuation.finish(throwing: error)
            }
        }
    }

    func stop() async {
        guard lock.withLock({
            if stopped { return false }
            stopped = true
            return true
        }) else { return }
        await capture.stop()
        inputContinuation.finish()
        audioLevelContinuation.finish()
        await analysisTask?.value
        eventContinuation.finish()
    }

    func cancel() async {
        await capture.stop()
        inputContinuation.finish()
        audioLevelContinuation.finish()
        await analyzer.cancelAndFinishNow()
        analysisTask?.cancel()
        resultTask?.cancel()
        eventContinuation.finish()
    }
}
