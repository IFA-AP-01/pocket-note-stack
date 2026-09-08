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
    case openAI

    var id: String { rawValue }
    var title: String {
        switch self {
        case .appleOnDevice: "Apple On-Device"
        case .geminiLive: "Google Gemini"
        case .openAI: "OpenAI"
        }
    }
}

enum AudioSource: String, CaseIterable, Codable, Identifiable {
    case microphone
    case screen
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: "Microphone"
        case .screen: "System Audio"
        case .both: "Both"
        }
    }
}

enum TranscriptEvent: Equatable, Sendable {
    case interim(String)
    case promoteInterim
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
    var audioLevels: AsyncStream<Float>? { get }
    func stop() async
    func cancel() async
}

extension DictationSession {
    var audioLevels: AsyncStream<Float>? { nil }
}

protocol DictationEngine: Sendable {
    func start(localeIdentifier: String?, deviceUID: String?, audioSource: AudioSource) async throws -> any DictationSession
}
