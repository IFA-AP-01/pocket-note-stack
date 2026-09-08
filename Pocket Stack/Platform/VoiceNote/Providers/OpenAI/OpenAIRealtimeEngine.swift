import Foundation

struct OpenAIRealtimeEngine: DictationEngine {
    let keychain: KeychainStore
    init(keychain: KeychainStore = KeychainStore()) { self.keychain = keychain }

    func readiness(for request: DictationRequest) async -> DictationReadiness {
        let key = try? keychain.string(for: "openai-api-key")?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key != nil, key?.isEmpty == false else {
            return .unavailable("OpenAI API key is not configured. Please enter your API key in Settings.")
        }
        return .ready
    }

    func start(_ request: DictationRequest) async throws -> any DictationSession {
        guard let key = try keychain.string(for: "openai-api-key")?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw DictationError.missingAPIKey
        }
        let (events, continuation) = AsyncThrowingStream.makeStream(of: TranscriptEvent.self)
        let socket = try await OpenAISocket.connect(
            apiKey: key,
            localeIdentifier: request.localeIdentifier,
            continuation: continuation
        )
        return try await RealtimeDictationSession.start(
            request: request,
            sampleRate: 24_000,
            events: events,
            continuation: continuation,
            transport: socket
        )
    }

    func testConnection() async throws {
        guard let key = try keychain.string(for: "openai-api-key")?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw DictationError.missingAPIKey
        }
        let socket = try await OpenAISocket.connect(apiKey: key, localeIdentifier: nil, continuation: nil)
        await socket.close()
    }
}
