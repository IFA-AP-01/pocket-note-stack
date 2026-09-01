import Foundation

struct GeminiLiveEngine: DictationEngine {
    let keychain: KeychainStore
    init(keychain: KeychainStore = KeychainStore()) { self.keychain = keychain }

    func start(localeIdentifier: String?, deviceUID: String?) async throws -> any DictationSession {
        guard let key = try keychain.string(for: "gemini-api-key")?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw DictationError.missingAPIKey
        }
        return try await GeminiDictationSession.create(apiKey: key, localeIdentifier: localeIdentifier, deviceUID: deviceUID)
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
    private let microphone: MicrophoneCapture
    private let encoder: PCM16StreamEncoder
    private var limitTask: Task<Void, Never>?
    private let lock = NSLock()
    private var stopped = false

    private init(
        events: AsyncThrowingStream<TranscriptEvent, Error>,
        continuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation,
        socket: GeminiSocket,
        microphone: MicrophoneCapture,
        encoder: PCM16StreamEncoder
    ) {
        self.events = events
        self.continuation = continuation
        self.socket = socket
        self.microphone = microphone
        self.encoder = encoder
    }

    static func create(apiKey: String, localeIdentifier: String?, deviceUID: String?) async throws -> GeminiDictationSession {
        let (events, continuation) = AsyncThrowingStream.makeStream(of: TranscriptEvent.self)
        let socket = try await GeminiSocket.connect(apiKey: apiKey, localeIdentifier: localeIdentifier, continuation: continuation)
        let encoder = PCM16StreamEncoder()
        let microphone = MicrophoneCapture { buffer in
            let chunks = encoder.encode(buffer)
            for chunk in chunks { Task { await socket.sendAudio(chunk) } }
        }
        let session = GeminiDictationSession(events: events, continuation: continuation, socket: socket, microphone: microphone, encoder: encoder)
        try await microphone.start(deviceUID: deviceUID)
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
        microphone.stop()
        if let tail = encoder.flush() { await socket.sendAudio(tail) }
        await socket.finishAudio()
        try? await Task.sleep(for: .seconds(2))
        await socket.close()
        continuation.finish()
    }

    func cancel() async {
        limitTask?.cancel()
        microphone.stop()
        await socket.close()
        continuation.finish()
    }
}

actor GeminiSocket {
    private let task: URLSessionWebSocketTask
    private let session: URLSession
    private let continuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation?
    private var receiveTask: Task<Void, Never>?

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

    func finishAudio() async {
        try? await sendJSON(["realtimeInput": ["audioStreamEnd": true]])
    }

    func close() {
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
                        continuation?.finish(throwing: NSError(domain: "Gemini", code: 2, userInfo: [NSLocalizedDescriptionKey: error]))
                        return
                    }
                    guard let content = root["serverContent"] as? [String: Any] else { continue }
                    if let interim = content["interimInputTranscription"] as? [String: Any], let text = interim["text"] as? String {
                        continuation?.yield(.interim(text))
                    }
                    if let final = content["inputTranscription"] as? [String: Any], let text = final["text"] as? String {
                        continuation?.yield(.final(text))
                    }
                }
            } catch {
                if !Task.isCancelled { continuation?.finish(throwing: error) }
            }
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
