import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor SQLiteNoteRepository: NoteRepository {
    enum RepositoryError: LocalizedError {
        case open(String)
        case statement(String)
        case corruptNote(String)

        var errorDescription: String? {
            switch self {
            case .open(let message): "Unable to open notes database: \(message)"
            case .statement(let message): "Notes database error: \(message)"
            case .corruptNote(let id): "Unable to decrypt note \(id)."
            }
        }
    }

    private var database: OpaquePointer?
    private let cipher: BodyCipher
    private var continuations: [UUID: AsyncStream<[Note]>.Continuation] = [:]

    init(url: URL? = nil, cipher: BodyCipher? = nil) throws {
        self.cipher = try cipher ?? BodyCipher()
        let databaseURL = try url ?? Self.defaultDatabaseURL()
        database = try Self.openDatabase(at: databaseURL)
    }

    deinit { sqlite3_close_v2(database) }

    func snapshots() async -> AsyncStream<[Note]> {
        let id = UUID()
        let initial = (try? load()) ?? []
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.yield(initial)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    func load() throws -> [Note] {
        let sql = "SELECT id,title,body,color,created,modified,archived,pinned,sort_order,custom_color,custom_title FROM notes ORDER BY sort_order ASC;"
        var statement: OpaquePointer?
        try prepare(sql, into: &statement)
        defer { sqlite3_finalize(statement) }
        var notes: [Note] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let idString = text(statement, 0)
            guard let id = UUID(uuidString: idString), let blob = sqlite3_column_blob(statement, 2) else { continue }
            let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 2)))
            guard let body = try? cipher.open(data) else { throw RepositoryError.corruptNote(idString) }
            notes.append(Note(
                id: id,
                title: text(statement, 1),
                customTitle: optionalText(statement, 10),
                body: body,
                colorIndex: Int(sqlite3_column_int(statement, 3)),
                customColorHex: optionalText(statement, 9),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
                modifiedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
                isArchived: sqlite3_column_int(statement, 6) != 0,
                isPinned: sqlite3_column_int(statement, 7) != 0,
                sortOrder: sqlite3_column_double(statement, 8)
            ))
        }
        return notes
    }

    func upsert(_ note: Note) throws {
        let sql = """
        INSERT INTO notes (id,title,body,color,created,modified,archived,pinned,sort_order,custom_color,custom_title)
        VALUES (?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET
        title=excluded.title,body=excluded.body,color=excluded.color,modified=excluded.modified,
        archived=excluded.archived,pinned=excluded.pinned,sort_order=excluded.sort_order,
        custom_color=excluded.custom_color,custom_title=excluded.custom_title;
        """
        var statement: OpaquePointer?
        try prepare(sql, into: &statement)
        defer { sqlite3_finalize(statement) }
        let sealed = try cipher.seal(note.body)
        sqlite3_bind_text(statement, 1, note.id.uuidString, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, note.title, -1, sqliteTransient)
        _ = sealed.withUnsafeBytes { sqlite3_bind_blob(statement, 3, $0.baseAddress, Int32(sealed.count), sqliteTransient) }
        sqlite3_bind_int(statement, 4, Int32(note.colorIndex))
        sqlite3_bind_double(statement, 5, note.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 6, note.modifiedAt.timeIntervalSince1970)
        sqlite3_bind_int(statement, 7, note.isArchived ? 1 : 0)
        sqlite3_bind_int(statement, 8, note.isPinned ? 1 : 0)
        sqlite3_bind_double(statement, 9, note.sortOrder)
        bindOptionalText(statement, 10, note.customColorHex)
        bindOptionalText(statement, 11, note.customTitle)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw currentError() }
        try publish()
    }

    func delete(id: UUID) throws {
        var statement: OpaquePointer?
        try prepare("DELETE FROM notes WHERE id=?;", into: &statement)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, id.uuidString, -1, sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw currentError() }
        try publish()
    }

    func ingest(_ notes: [Note]) throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            for note in notes { try upsertWithoutPublish(note) }
            try execute("COMMIT;")
            try publish()
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func upsertWithoutPublish(_ note: Note) throws {
        let sql = "INSERT OR REPLACE INTO notes (id,title,body,color,created,modified,archived,pinned,sort_order,custom_color,custom_title) VALUES (?,?,?,?,?,?,?,?,?,?,?);"
        var statement: OpaquePointer?
        try prepare(sql, into: &statement)
        defer { sqlite3_finalize(statement) }
        let sealed = try cipher.seal(note.body)
        sqlite3_bind_text(statement, 1, note.id.uuidString, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, note.title, -1, sqliteTransient)
        _ = sealed.withUnsafeBytes { sqlite3_bind_blob(statement, 3, $0.baseAddress, Int32(sealed.count), sqliteTransient) }
        sqlite3_bind_int(statement, 4, Int32(note.colorIndex))
        sqlite3_bind_double(statement, 5, note.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 6, note.modifiedAt.timeIntervalSince1970)
        sqlite3_bind_int(statement, 7, note.isArchived ? 1 : 0)
        sqlite3_bind_int(statement, 8, note.isPinned ? 1 : 0)
        sqlite3_bind_double(statement, 9, note.sortOrder)
        bindOptionalText(statement, 10, note.customColorHex)
        bindOptionalText(statement, 11, note.customTitle)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw currentError() }
    }

    private static func openDatabase(at url: URL) throws -> OpaquePointer? {
        var database: OpaquePointer?
        if sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
            sqlite3_close_v2(database)
            throw RepositoryError.open(message)
        }
        func run(_ sql: String) throws {
            var message: UnsafeMutablePointer<CChar>?
            guard sqlite3_exec(database, sql, nil, nil, &message) == SQLITE_OK else {
                let detail = message.map { String(cString: $0) } ?? "Unknown SQLite error"
                sqlite3_free(message)
                throw RepositoryError.statement(detail)
            }
        }
        try run("PRAGMA journal_mode=WAL;")
        try run("PRAGMA synchronous=NORMAL;")
        try run("""
        CREATE TABLE IF NOT EXISTS notes (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL DEFAULT '',
          body BLOB NOT NULL,
          color INTEGER NOT NULL DEFAULT 0,
          created REAL NOT NULL,
          modified REAL NOT NULL,
          archived INTEGER NOT NULL DEFAULT 0,
          pinned INTEGER NOT NULL DEFAULT 0,
          sort_order REAL NOT NULL DEFAULT 0,
          custom_color TEXT,
          custom_title TEXT
        );
        """)
        if sqlite3_table_column_metadata(database, nil, "notes", "custom_color", nil, nil, nil, nil, nil) != SQLITE_OK {
            try run("ALTER TABLE notes ADD COLUMN custom_color TEXT;")
        }
        if sqlite3_table_column_metadata(database, nil, "notes", "custom_title", nil, nil, nil, nil, nil) != SQLITE_OK {
            try run("ALTER TABLE notes ADD COLUMN custom_title TEXT;")
        }
        try run("CREATE INDEX IF NOT EXISTS idx_notes_archived_order ON notes(archived,sort_order);")
        try run("PRAGMA user_version=3;")
        return database
    }

    private func execute(_ sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &message) == SQLITE_OK else {
            let detail = message.map { String(cString: $0) } ?? "Unknown SQLite error"
            sqlite3_free(message)
            throw RepositoryError.statement(detail)
        }
    }

    private func prepare(_ sql: String, into statement: inout OpaquePointer?) throws {
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw currentError() }
    }

    private func currentError() -> RepositoryError {
        RepositoryError.statement(String(cString: sqlite3_errmsg(database)))
    }

    private func text(_ statement: OpaquePointer?, _ column: Int32) -> String {
        sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
    }

    private func optionalText(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        let value = text(statement, column)
        return value.isEmpty ? nil : value
    }

    private func bindOptionalText(_ statement: OpaquePointer?, _ column: Int32, _ value: String?) {
        if let value { sqlite3_bind_text(statement, column, value, -1, sqliteTransient) }
        else { sqlite3_bind_null(statement, column) }
    }

    private func publish() throws {
        let notes = try load()
        continuations.values.forEach { $0.yield(notes) }
    }

    private func removeContinuation(_ id: UUID) { continuations[id] = nil }

    private static func defaultDatabaseURL() throws -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pocket Stack", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("notes.sqlite3")
    }
}
