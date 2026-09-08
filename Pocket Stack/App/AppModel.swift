import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private let repository: any NoteRepository
    private var observationTask: Task<Void, Never>?
    private var undoTask: Task<Void, Never>?
    private(set) var notes: [Note] = []
    private(set) var errorMessage: String?
    private(set) var pendingDelete: Note?

    init(repository: any NoteRepository) {
        self.repository = repository
    }

    func start() {
        guard observationTask == nil else { return }
        observationTask = Task { [weak self, repository] in
            let stream = await repository.snapshots()
            for await snapshot in stream {
                guard let self else { return }
                if notes != snapshot {
                    notes = snapshot
                    NotificationCenter.default.post(name: .pocketStackNotesDidChange, object: self)
                }
                if snapshot.isEmpty { await seedWelcomeNote() }
            }
        }
    }

    var activeNotes: [Note] { notes.filter { !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder } }
    var archivedNotes: [Note] { notes.filter(\.isArchived).sorted { $0.modifiedAt > $1.modifiedAt } }

    func note(id: UUID) -> Note? { notes.first { $0.id == id } }

    @discardableResult
    func create(body: String = "") -> Note {
        let order = (activeNotes.map(\.sortOrder).min() ?? 0) - 1
        let note = Note(body: body, colorIndex: notes.count % NotePalette.colors.count, sortOrder: order)
        notes.insert(note, at: 0)
        persist(note)
        return note
    }

    func updateBody(id: UUID, body: String) {
        guard var note = note(id: id), note.body != body else { return }
        note.body = body
        note.title = Note.derivedTitle(from: body)
        note.modifiedAt = .now
        persist(note)
    }

    func updateContent(id: UUID, body: String, customTitle: String?) {
        guard var note = note(id: id) else { return }
        let trimmedTitle = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedTitle = trimmedTitle.isEmpty ? nil : String(trimmedTitle.prefix(120))
        let derivedTitle = Note.derivedTitle(from: body)
        guard note.body != body || note.title != derivedTitle || note.customTitle != normalizedTitle else { return }
        note.body = body
        note.title = derivedTitle
        note.customTitle = normalizedTitle
        note.modifiedAt = .now
        persist(note)
    }

    func togglePin(id: UUID) { mutate(id) { $0.isPinned.toggle() } }
    func cycleColor(id: UUID) {
        mutate(id) {
            $0.colorIndex = ($0.colorIndex + 1) % NotePalette.colors.count
            $0.customColorHex = nil
        }
    }
    func setColor(id: UUID, index: Int) {
        mutate(id) {
            $0.colorIndex = index
            $0.customColorHex = nil
        }
    }
    func setCustomColor(id: UUID, hex: String) {
        mutate(id) { $0.customColorHex = hex }
    }
    func setArchived(id: UUID, _ archived: Bool) {
        mutate(id) {
            $0.isArchived = archived
            if !archived { $0.sortOrder = (activeNotes.map(\.sortOrder).min() ?? 0) - 1 }
        }
    }

    func delete(id: UUID) {
        guard let note = note(id: id) else { return }
        pendingDelete = note
        notes.removeAll { $0.id == id }
        NotificationCenter.default.post(name: .pocketStackNotesDidChange, object: self)
        Task { await perform { try await self.repository.delete(id: id) } }
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.pendingDelete = nil
        }
    }

    func undoDelete() {
        guard let note = pendingDelete else { return }
        undoTask?.cancel()
        pendingDelete = nil
        notes.append(note)
        NotificationCenter.default.post(name: .pocketStackNotesDidChange, object: self)
        persist(note)
    }

    func reorder(id: UUID, before targetID: UUID?) {
        guard var moved = note(id: id) else { return }
        let list = activeNotes.filter { $0.id != id }
        if let targetID, let target = list.firstIndex(where: { $0.id == targetID }) {
            let upper = list[target].sortOrder
            let lower = target > 0 ? list[target - 1].sortOrder : upper - 2
            moved.sortOrder = (lower + upper) / 2
        } else {
            moved.sortOrder = (list.map(\.sortOrder).max() ?? 0) + 1
        }
        persist(moved)
    }

    func ingest(_ imported: [Note]) {
        let existing = Set(notes.map(\.id))
        var order = (notes.map(\.sortOrder).min() ?? 0) - 1
        let normalized = imported.map { source in
            var note = source
            if existing.contains(note.id) { note.id = UUID() }
            note.sortOrder = order
            order -= 1
            return note
        }
        Task { await perform { try await self.repository.ingest(normalized) } }
    }

    enum FilterState: String, CaseIterable, Identifiable {
        case all = "All"
        case active = "Active"
        case archived = "Archived"
        var id: String { rawValue }
    }

    func search(_ query: String, filter: FilterState) -> [Note] {
        let source: [Note]
        switch filter {
        case .all: source = notes.sorted { $0.modifiedAt > $1.modifiedAt }
        case .active: source = activeNotes.sorted { $0.modifiedAt > $1.modifiedAt }
        case .archived: source = archivedNotes
        }
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return source }
        return source.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(term) || $0.body.localizedCaseInsensitiveContains(term)
        }
    }

    private func mutate(_ id: UUID, change: (inout Note) -> Void) {
        guard var note = note(id: id) else { return }
        change(&note)
        note.modifiedAt = .now
        persist(note)
    }

    private func persist(_ note: Note) {
        Task { await perform { try await self.repository.upsert(note) } }
    }

    private func perform(_ operation: @escaping @Sendable () async throws -> Void) async {
        do { try await operation(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    private func seedWelcomeNote() async {
        guard notes.isEmpty else { return }
        let note = Note(body: """
        Welcome to Pocket Stack

        Move the pointer to the screen edge to reveal your notes.

        ⌥⌘N  New note
        ⌥⌘A  All notes
        ⌥⌘L  Archive
        """, colorIndex: 0, sortOrder: 0)
        await perform { try await self.repository.upsert(note) }
    }
}
