import Foundation

protocol NoteRepository: Sendable {
    func snapshots() async -> AsyncStream<[Note]>
    func load() async throws -> [Note]
    func upsert(_ note: Note) async throws
    func delete(id: UUID) async throws
    func ingest(_ notes: [Note]) async throws
}
