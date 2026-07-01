import Foundation
import GRDB

/// SQLite-backed store (GRDB). Owns the schema: `note`, `embedding`, and an
/// FTS5 mirror kept in sync by triggers (ARCHITECTURE.md §4).
public final class NoteStore: @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    public init(path: URL) throws {
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        dbQueue = try DatabaseQueue(path: path.path)
        try migrator.migrate(dbQueue)
    }

    /// In-memory store for tests.
    public init(inMemory: Bool) throws {
        dbQueue = try DatabaseQueue()
        try migrator.migrate(dbQueue)
    }

    private var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "note") { t in
                t.column("id", .text).primaryKey()
                t.column("body", .text).notNull()
                t.column("title", .text).notNull()
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull().indexed()
            }
            try db.create(table: "embedding") { t in
                t.column("note_id", .text).notNull()
                    .references("note", onDelete: .cascade)
                t.column("model", .text).notNull()
                t.column("dim", .integer).notNull()
                t.column("vector", .blob).notNull()
                t.primaryKey(["note_id", "model"])
            }
            try db.create(virtualTable: "note_fts", using: FTS5()) { t in
                t.synchronize(withTable: "note")
                t.column("title")
                t.column("body")
                t.tokenizer = .porter(wrapping: .unicode61())
            }
        }
        return m
    }

    // MARK: - CRUD

    @discardableResult
    public func create(body: String) throws -> Note {
        let note = Note(body: body)
        try dbQueue.write { db in try note.insert(db) }
        return note
    }

    public func update(id: String, body: String) throws -> Note? {
        try dbQueue.write { db in
            guard var note = try Note.fetchOne(db, key: id) else { return nil }
            note.body = body
            note.title = Note.deriveTitle(from: body)
            note.updatedAt = Date()
            try note.update(db)
            return note
        }
    }

    public func delete(id: String) throws {
        _ = try dbQueue.write { db in try Note.deleteOne(db, key: id) }
    }

    public func fetch(id: String) throws -> Note? {
        try dbQueue.read { db in try Note.fetchOne(db, key: id) }
    }

    public func fetch(ids: [String]) throws -> [String: Note] {
        try dbQueue.read { db in
            let notes = try Note.filter(keys: ids).fetchAll(db)
            return Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        }
    }

    public func recent(limit: Int) throws -> [Note] {
        try dbQueue.read { db in
            try Note.order(Column("updatedAt").desc).limit(limit).fetchAll(db)
        }
    }

    public func allIDs() throws -> [String] {
        try dbQueue.read { db in try String.fetchAll(db, sql: "SELECT id FROM note") }
    }

    // MARK: - Embeddings

    public func saveEmbedding(noteID: String, model: String, vector: [Float]) throws {
        let blob = vector.withUnsafeBufferPointer { Data(buffer: $0) }
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO embedding (note_id, model, dim, vector) VALUES (?, ?, ?, ?)
                ON CONFLICT(note_id, model) DO UPDATE SET dim = excluded.dim, vector = excluded.vector
                """, arguments: [noteID, model, vector.count, blob])
        }
    }

    /// All (noteID, vector) pairs stored for a given encoder, for index warm-up.
    public func loadEmbeddings(model: String) throws -> [(id: String, vector: [Float])] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db,
                sql: "SELECT note_id, vector FROM embedding WHERE model = ?", arguments: [model])
            return rows.map { row in
                let data: Data = row["vector"]
                let vec = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                return (row["note_id"], vec)
            }
        }
    }

    /// IDs of notes lacking an embedding for `model` (need background indexing).
    public func idsMissingEmbedding(model: String) throws -> [String] {
        try dbQueue.read { db in
            try String.fetchAll(db, sql: """
                SELECT n.id FROM note n
                LEFT JOIN embedding e ON e.note_id = n.id AND e.model = ?
                WHERE e.note_id IS NULL
                """, arguments: [model])
        }
    }

    // MARK: - Lexical search (FTS5 / BM25)

    /// Returns (id, bm25) for notes matching `query`. Lower bm25 = more relevant.
    public func lexicalSearch(_ query: String, limit: Int) throws -> [(id: String, bm25: Double)] {
        let pattern = Self.ftsPattern(query)
        guard !pattern.isEmpty else { return [] }
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT n.id AS id, bm25(note_fts) AS score
                FROM note_fts
                JOIN note n ON n.rowid = note_fts.rowid
                WHERE note_fts MATCH ?
                ORDER BY score
                LIMIT ?
                """, arguments: [pattern, limit])
            return rows.map { (id: $0["id"], bm25: $0["score"]) }
        }
    }

    /// Build a forgiving FTS5 MATCH pattern: each term prefix-matched, OR-joined.
    static func ftsPattern(_ query: String) -> String {
        let terms = query
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
            .map { "\($0)*" }
        return terms.joined(separator: " OR ")
    }
}
