import AVFoundation
import Foundation

final class RealtimeDictationSession: DictationSession, @unchecked Sendable {
    let events: AsyncThrowingStream<TranscriptEvent, Error>

    private let continuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation
    private let transport: any RealtimeTranscriptionTransport
    private let capture: AudioCapturePipeline
    private var limitTask: Task<Void, Never>?
    private let lock = NSLock()
    private var stopped = false

    private init(
        events: AsyncThrowingStream<TranscriptEvent, Error>,
        continuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation,
        transport: any RealtimeTranscriptionTransport,
        capture: AudioCapturePipeline
    ) {
        self.events = events
        self.continuation = continuation
        self.transport = transport
        self.capture = capture
    }

    static func start(
        request: DictationRequest,
        sampleRate: Double,
        events: AsyncThrowingStream<TranscriptEvent, Error>,
        continuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation,
        transport: any RealtimeTranscriptionTransport
    ) async throws -> RealtimeDictationSession {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw DictationError.audioFormatUnavailable
        }

        let encoder = PCM16StreamEncoder(sampleRate: sampleRate)
        let capture = AudioCapturePipeline(request: request, targetFormat: format) { buffer in
            for chunk in encoder.encode(buffer) {
                Task { await transport.sendAudio(chunk) }
            }
        }
        let session = RealtimeDictationSession(
            events: events,
            continuation: continuation,
            transport: transport,
            capture: capture
        )
        do {
            try await capture.start()
        } catch {
            await transport.close()
            throw error
        }
        session.limitTask = Task {
            try? await Task.sleep(for: .seconds(570))
            guard !Task.isCancelled else { return }
            await session.stop()
        }
        return session
    }

    func stop() async {
        guard lock.withLock({
            if stopped { return false }
            stopped = true
            return true
        }) else { return }
        limitTask?.cancel()
        await capture.stop()
        await transport.finishAudioAndWaitForFinal()
        await transport.close()
        continuation.finish()
    }

    func cancel() async {
        limitTask?.cancel()
        await capture.stop()
        await transport.close()
        continuation.finish()
    }
}
