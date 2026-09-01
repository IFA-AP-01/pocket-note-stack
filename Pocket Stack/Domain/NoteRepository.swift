import Foundation

protocol NoteRepository: Sendable {
    func snapshots() async -> AsyncStream<[Note]>
    func load() async throws -> [Note]
    func upsert(_ note: Note) async throws
    func delete(id: UUID) async throws
    func ingest(_ notes: [Note]) async throws
}

enum SpeechProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case appleOnDevice
    case geminiLive

    var id: String { rawValue }
    var title: String {
        switch self {
        case .appleOnDevice: "Apple On-Device"
        case .geminiLive: "Google Gemini Live"
        }
    }
}

enum TranscriptEvent: Equatable, Sendable {
    case interim(String)
    case final(String)
}

enum DictationState: Equatable, Sendable {
    case idle
    case preparing
    case listening
    case finalizing
    case failed(String)
}

protocol DictationSession: Sendable {
    var events: AsyncThrowingStream<TranscriptEvent, Error> { get }
    func stop() async
    func cancel() async
}

protocol DictationEngine: Sendable {
    func start(localeIdentifier: String?, deviceUID: String?) async throws -> any DictationSession
}
