import Foundation

protocol DictationSession: Sendable {
    var events: AsyncThrowingStream<TranscriptEvent, Error> { get }
    var audioLevels: AsyncStream<Float>? { get }
    func stop() async
    func cancel() async
}

extension DictationSession {
    var audioLevels: AsyncStream<Float>? { nil }
}

protocol DictationEngine: Sendable {
    func readiness(for request: DictationRequest) async -> DictationReadiness
    func start(_ request: DictationRequest) async throws -> any DictationSession
}

protocol DictationEngineFactory: Sendable {
    func makeEngine(for provider: SpeechProvider) -> any DictationEngine
}
