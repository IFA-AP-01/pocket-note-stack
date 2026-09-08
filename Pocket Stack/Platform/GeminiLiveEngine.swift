import Foundation

struct GeminiLiveEngine: DictationEngine {
    let keychain: KeychainStore
    init(keychain: KeychainStore = KeychainStore()) { self.keychain = keychain }

    func start(localeIdentifier: String?, deviceUID: String?, audioSource: AudioSource) async throws -> any DictationSession {
        guard let key = try keychain.string(for: "gemini-api-key")?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw DictationError.missingAPIKey
        }
        return try await GeminiDictationSession.create(apiKey: key, localeIdentifier: localeIdentifier, deviceUID: deviceUID, audioSource: audioSource)
    }

    func testConnection() async throws {
        guard let key = try keychain.string(for: "gemini-api-key")?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw DictationError.missingAPIKey
        }
        let socket = try await GeminiSocket.connect(apiKey: key, localeIdentifier: nil, continuation: nil)
        await socket.close()
    }
}

final class GeminiDictationSession: DictationSession, @unchecked Sendable {
    let events: AsyncThrowingStream<TranscriptEvent, Error>
    private let continuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation
    private let socket: GeminiSocket
    private let capture: CompositeAudioCapture
    private var limitTask: Task<Void, Never>?
    private let lock = NSLock()
    private var stopped = false

    private init(
        events: AsyncThrowingStream<TranscriptEvent, Error>,
        continuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation,
        socket: GeminiSocket,
        capture: CompositeAudioCapture
    ) {
        self.events = events
        self.continuation = continuation
        self.socket = socket
        self.capture = capture
    }

    static func create(apiKey: String, localeIdentifier: String?, deviceUID: String?, audioSource: AudioSource) async throws -> GeminiDictationSession {
        let (events, continuation) = AsyncThrowingStream.makeStream(of: TranscriptEvent.self)
        let socket = try await GeminiSocket.connect(apiKey: apiKey, localeIdentifier: localeIdentifier, continuation: continuation)
        let capture = CompositeAudioCapture(audioSource: audioSource) { chunk in
            Task { await socket.sendAudio(chunk) }
        }
        let session = GeminiDictationSession(events: events, continuation: continuation, socket: socket, capture: capture)
        try await capture.start(deviceUID: deviceUID)
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
}

actor GeminiSocket {
    private let task: URLSessionWebSocketTask
    private let session: URLSession
    private let continuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation?
    private var receiveTask: Task<Void, Never>?
    private var hasPendingInterim = false
    private var finalizationWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    private init(task: URLSessionWebSocketTask, session: URLSession, continuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation?) {
        self.task = task
        self.session = session
        self.continuation = continuation
    }

    static func connect(
        apiKey: String,
        localeIdentifier: String?,
        continuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation?
    ) async throws -> GeminiSocket {
        var components = URLComponents(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent")!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else { throw DictationError.invalidServerResponse }
        let session = URLSession(configuration: .ephemeral)
        let task = session.webSocketTask(with: url)
        let socket = GeminiSocket(task: task, session: session, continuation: continuation)
        task.resume()
        var inputConfig: [String: Any] = ["languageCodes": []]
        if let localeIdentifier, localeIdentifier != "auto" { inputConfig["languageCodes"] = [localeIdentifier] }
        try await socket.sendJSON([
            "setup": [
                "model": "models/gemini-3.5-transcribe-live",
                "generationConfig": ["responseModalities": ["TEXT"]],
                "inputAudioTranscription": inputConfig,
            ],
        ])
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
        if let error = serverError(object) { throw NSError(domain: "Gemini", code: 1, userInfo: [NSLocalizedDescriptionKey: error]) }
        guard object["setupComplete"] != nil else { throw DictationError.invalidServerResponse }
        await socket.startReceiving()
        return socket
    }

    func sendAudio(_ data: Data) async {
        guard !data.isEmpty else { return }
        try? await sendJSON([
            "realtimeInput": [
                "audio": ["data": data.base64EncodedString(), "mimeType": "audio/pcm;rate=16000"],
            ],
        ])
    }

    func finishAudioAndWaitForFinal() async {
        try? await sendJSON(["realtimeInput": ["audioStreamEnd": true]])
        guard hasPendingInterim else { return }

        let waiterID = UUID()
        await withCheckedContinuation { continuation in
            guard hasPendingInterim else {
                continuation.resume()
                return
            }
            finalizationWaiters[waiterID] = continuation
            Task {
                try? await Task.sleep(for: .seconds(1))
                self.resumeFinalizationWaiter(waiterID)
            }
        }
    }

    func close() {
        resumeAllFinalizationWaiters()
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
                        await self.resumeAllFinalizationWaiters()
                        continuation?.finish(throwing: NSError(domain: "Gemini", code: 2, userInfo: [NSLocalizedDescriptionKey: error]))
                        return
                    }
                    guard let content = root["serverContent"] as? [String: Any] else { continue }
                    if let interim = content["interimInputTranscription"] as? [String: Any], let text = interim["text"] as? String {
                        await self.noteInterim(text)
                        continuation?.yield(.interim(text))
                    }
                    if let final = content["inputTranscription"] as? [String: Any], let text = final["text"] as? String {
                        await self.noteFinal()
                        continuation?.yield(.final(text))
                    }
                }
            } catch {
                await self.resumeAllFinalizationWaiters()
                if !Task.isCancelled { continuation?.finish(throwing: error) }
            }
        }
    }

    private func noteInterim(_ text: String) {
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hasPendingInterim = true
        }
    }

    private func noteFinal() {
        hasPendingInterim = false
        resumeAllFinalizationWaiters()
    }

    private func resumeFinalizationWaiter(_ id: UUID) {
        finalizationWaiters.removeValue(forKey: id)?.resume()
    }

    private func resumeAllFinalizationWaiters() {
        let waiters = finalizationWaiters.values
        finalizationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
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
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw DictationError.invalidServerResponse }
        return object
    }

    private static func serverError(_ object: [String: Any]) -> String? {
        (object["error"] as? [String: Any])?["message"] as? String
    }
}
