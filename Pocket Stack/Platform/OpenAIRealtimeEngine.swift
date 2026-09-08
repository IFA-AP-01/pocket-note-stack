import Foundation

private let openAITranscriptionModel = "gpt-live-transcribe"

struct OpenAIRealtimeEngine: DictationEngine {
    let keychain: KeychainStore
    init(keychain: KeychainStore = KeychainStore()) { self.keychain = keychain }

    func start(localeIdentifier: String?, deviceUID: String?, audioSource: AudioSource) async throws -> any DictationSession {
        guard let key = try keychain.string(for: "openai-api-key")?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw DictationError.missingAPIKey
        }
        return try await OpenAIDictationSession.create(apiKey: key, localeIdentifier: localeIdentifier, deviceUID: deviceUID, audioSource: audioSource)
    }

    func testConnection() async throws {
        guard let key = try keychain.string(for: "openai-api-key")?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw DictationError.missingAPIKey
        }
        let socket = try await OpenAISocket.connect(apiKey: key, localeIdentifier: nil, continuation: nil)
        await socket.close()
    }
}

final class OpenAIDictationSession: DictationSession, @unchecked Sendable {
    let events: AsyncThrowingStream<TranscriptEvent, Error>
    private let continuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation
    private let socket: OpenAISocket
    private let capture: CompositeAudioCapture
    private var limitTask: Task<Void, Never>?
    private let lock = NSLock()
    private var stopped = false

    private init(
        events: AsyncThrowingStream<TranscriptEvent, Error>,
        continuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation,
        socket: OpenAISocket,
        capture: CompositeAudioCapture
    ) {
        self.events = events
        self.continuation = continuation
        self.socket = socket
        self.capture = capture
    }

    static func create(apiKey: String, localeIdentifier: String?, deviceUID: String?, audioSource: AudioSource) async throws -> OpenAIDictationSession {
        let (events, continuation) = AsyncThrowingStream.makeStream(of: TranscriptEvent.self)
        let socket = try await OpenAISocket.connect(apiKey: apiKey, localeIdentifier: localeIdentifier, continuation: continuation)
        let capture = CompositeAudioCapture(audioSource: audioSource) { chunk in
            // Resample 16kHz PCM16 to 24kHz PCM16 for OpenAI Realtime
            let resampled = Self.resample16kTo24k(data: chunk)
            Task { await socket.sendAudio(resampled) }
        }
        let session = OpenAIDictationSession(events: events, continuation: continuation, socket: socket, capture: capture)
        do {
            try await capture.start(deviceUID: deviceUID)
        } catch {
            await socket.close()
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
        guard lock.withLock({ if stopped { return false }; stopped = true; return true }) else { return }
        limitTask?.cancel()
        await capture.stop()
        await socket.finishAudioAndWaitForFinal()
        await socket.close()
        continuation.finish()
    }

    func cancel() async {
        limitTask?.cancel()
        await capture.stop()
        await socket.close()
        continuation.finish()
    }

    /// Resamples 16-bit mono PCM from 16kHz to 24kHz (1.5x upsample) using linear interpolation.
    static func resample16kTo24k(data: Data) -> Data {
        let sampleCount = data.count / 2
        guard sampleCount > 1 else { return data }

        return data.withUnsafeBytes { rawBuffer -> Data in
            guard let srcSamples = rawBuffer.bindMemory(to: Int16.self).baseAddress else {
                return data
            }

            let dstSampleCount = Int(Double(sampleCount) * 1.5)
            var dstData = Data(count: dstSampleCount * 2)

            dstData.withUnsafeMutableBytes { dstBuffer in
                guard let dstSamples = dstBuffer.bindMemory(to: Int16.self).baseAddress else { return }

                for i in 0..<dstSampleCount {
                    let srcPos = Double(i) / 1.5
                    let idx0 = Int(srcPos)
                    let frac = srcPos - Double(idx0)

                    if idx0 + 1 < sampleCount {
                        let s0 = Double(srcSamples[idx0])
                        let s1 = Double(srcSamples[idx0 + 1])
                        let interpolated = s0 + frac * (s1 - s0)
                        dstSamples[i] = Int16(clamping: Int(interpolated))
                    } else {
                        dstSamples[i] = srcSamples[min(idx0, sampleCount - 1)]
                    }
                }
            }

            return dstData
        }
    }
}

actor OpenAISocket {
    private let task: URLSessionWebSocketTask
    private let session: URLSession
    private let continuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation?
    private var receiveTask: Task<Void, Never>?
    private var hasPendingTranscript = false
    private var currentTranscript = ""
    private var finalizationWaiter: CheckedContinuation<Void, Never>?
    private var sentAudioChunks = 0

    private init(task: URLSessionWebSocketTask, session: URLSession, continuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation?) {
        self.task = task
        self.session = session
        self.continuation = continuation
    }

    static func connect(
        apiKey: String,
        localeIdentifier: String?,
        continuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation?
    ) async throws -> OpenAISocket {
        guard let url = URL(string: "wss://api.openai.com/v1/realtime?intent=transcription") else {
            throw DictationError.invalidServerResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .ephemeral)
        let task = session.webSocketTask(with: request)
        let socket = OpenAISocket(task: task, session: session, continuation: continuation)
        task.resume()

        // Do not start audio capture until the dedicated transcription session is confirmed.
        let first = try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
            group.addTask { try await task.receive() }
            group.addTask {
                try await Task.sleep(for: .seconds(8))
                throw DictationError.timedOut
            }
            guard let result = try await group.next() else { throw DictationError.timedOut }
            group.cancelAll()
            return result
        }

        let object = try decode(first)
        if let error = serverError(object) {
            throw NSError(domain: "OpenAI", code: 1, userInfo: [NSLocalizedDescriptionKey: error])
        }
        guard let type = object["type"] as? String,
              type == "session.created" || type == "transcription_session.created" else {
            throw DictationError.invalidServerResponse
        }

        var transcription: [String: Any] = ["model": openAITranscriptionModel]
        if let localeIdentifier, localeIdentifier != "auto" {
            transcription["languages"] = [localeIdentifier]
        }
        let sessionUpdate: [String: Any] = [
            "type": "session.update",
            "session": [
                "type": "transcription",
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": 24_000],
                        "transcription": transcription,
                        "turn_detection": NSNull()
                    ]
                ]
            ]
        ]
        try await socket.sendJSON(sessionUpdate)

        let updated = try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
            group.addTask { try await task.receive() }
            group.addTask {
                try await Task.sleep(for: .seconds(8))
                throw DictationError.timedOut
            }
            guard let result = try await group.next() else { throw DictationError.timedOut }
            group.cancelAll()
            return result
        }
        let updatedObject = try decode(updated)
        let updatedType = updatedObject["type"] as? String ?? "missing-type"
        if let error = serverError(updatedObject) {
            throw NSError(domain: "OpenAI", code: 1, userInfo: [NSLocalizedDescriptionKey: error])
        }
        guard updatedType == "session.updated" || updatedType == "transcription_session.updated" else {
            throw DictationError.invalidServerResponse
        }

        await socket.startReceiving()
        return socket
    }

    func sendAudio(_ data: Data) async {
        guard !data.isEmpty else { return }
        do {
            try await sendJSON([
                "type": "input_audio_buffer.append",
                "audio": data.base64EncodedString()
            ])
            sentAudioChunks += 1
        } catch {
            continuation?.finish(throwing: error)
        }
    }

    func finishAudioAndWaitForFinal() async {
        do {
            try await sendJSON(["type": "input_audio_buffer.commit"])
        } catch {
            return
        }
        guard sentAudioChunks > 0 else { return }

        await withCheckedContinuation { continuation in
            finalizationWaiter = continuation
            Task {
                try? await Task.sleep(for: .seconds(8))
                self.resumeFinalizationWaiter()
            }
        }
    }

    func close() {
        resumeFinalizationWaiter()
        receiveTask?.cancel()
        task.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }

    private func startReceiving() {
        receiveTask = Task { [weak self] in
            guard let self else { return }
            do {
                while !Task.isCancelled {
                    let message = try await task.receive()
                    let root = try Self.decode(message)

                    if let error = Self.serverError(root) {
                        await self.finishPendingTranscript()
                        continuation?.finish(throwing: NSError(domain: "OpenAI", code: 2, userInfo: [NSLocalizedDescriptionKey: error]))
                        return
                    }

                    guard let type = root["type"] as? String else { continue }

                    switch type {
                    case "conversation.item.input_audio_transcription.delta":
                        if let delta = root["delta"] as? String {
                            let transcript = await self.appendTranscriptDelta(delta)
                            continuation?.yield(.interim(transcript))
                        }
                    case "conversation.item.input_audio_transcription.completed":
                        if let transcript = root["transcript"] as? String {
                            await self.finishPendingTranscript()
                            continuation?.yield(.final(transcript))
                        }
                    default:
                        break
                    }
                }
            } catch {
                await self.finishPendingTranscript()
                if !Task.isCancelled {
                    continuation?.finish(throwing: error)
                }
            }
        }
    }

    private func appendTranscriptDelta(_ delta: String) -> String {
        currentTranscript += delta
        if !delta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hasPendingTranscript = true
        }
        return currentTranscript
    }

    private func finishPendingTranscript() {
        hasPendingTranscript = false
        currentTranscript = ""
        resumeFinalizationWaiter()
    }

    private func resumeFinalizationWaiter() {
        finalizationWaiter?.resume()
        finalizationWaiter = nil
    }

    private func sendJSON(_ object: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        try await task.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private static func decode(_ message: URLSessionWebSocketTask.Message) throws -> [String: Any] {
        let data: Data
        switch message {
        case .data(let value): data = value
        case .string(let value): data = Data(value.utf8)
        @unknown default: throw DictationError.invalidServerResponse
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DictationError.invalidServerResponse
        }
        return object
    }

    private static func serverError(_ object: [String: Any]) -> String? {
        if let error = object["error"] as? [String: Any] {
            return error["message"] as? String
        }
        return nil
    }
}
