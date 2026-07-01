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
        try Self.makeMigrator().migrate(dbQueue)
    }

    /// In-memory store for tests.
    public init(inMemory: Bool) throws {
        dbQueue = try DatabaseQueue()
        try Self.makeMigrator().migrate(dbQueue)
    }

    /// The schema migrator. Exposed (internal) so tests can simulate an older
    /// database by migrating only up to a given version (e.g. `upTo: "v1"`).
    static func makeMigrator() -> DatabaseMigrator {
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
        m.registerMigration("v2") { db in
            // Add spaceId column to note table
            try db.alter(table: "note") { t in
                t.add(column: "spaceId", .text)
            }
            // Create space table
            try db.create(table: "space") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull().unique()
                t.column("createdAt", .double).notNull()
            }
            // Create tag table
            try db.create(table: "tag") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull().unique()
            }
            // Create noteTag junction table
            try db.create(table: "noteTag") { t in
                t.column("noteId", .text).notNull()
                    .references("note", onDelete: .cascade)
                t.column("tagId", .text).notNull()
                    .references("tag", onDelete: .cascade)
                t.primaryKey(["noteId", "tagId"])
            }
            // Create noteLink table for directional links
            try db.create(table: "noteLink") { t in
                t.column("fromNoteId", .text).notNull()
                    .references("note", onDelete: .cascade)
                t.column("toNoteId", .text).notNull()
                    .references("note", onDelete: .cascade)
                t.column("kind", .text).notNull()
                t.primaryKey(["fromNoteId", "toNoteId", "kind"])
            }
        }
        return m
    }

    // MARK: - CRUD

    @discardableResult
    public func create(body: String) throws -> Note {
        let note = Note(body: body)
        try dbQueue.write { db in try note.insert(db) }
        // Extract and sync tags from body
        let tagNames = Note.extractTags(from: body)
        try setTags(noteID: note.id, names: tagNames)
        return note
    }

    public func update(id: String, body: String) throws -> Note? {
        let result: Note? = try dbQueue.write { db in
            guard var note = try Note.fetchOne(db, key: id) else { return nil }
            note.body = body
            note.title = Note.deriveTitle(from: body)
            note.updatedAt = Date()
            try note.update(db)
            return note
        }
        guard result != nil else { return nil }
        // Extract and sync tags from body
        let tagNames = Note.extractTags(from: body)
        try setTags(noteID: id, names: tagNames)
        return try fetch(id: id)
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

    // MARK: - Spaces

    @discardableResult
    public func createSpace(name: String) throws -> Space {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        return try dbQueue.write { db in
            // Check if a space with this case-insensitive name already exists
            if let existing = try Space.fetchOne(db,
                sql: "SELECT * FROM space WHERE LOWER(name) = LOWER(?)", arguments: [trimmedName]) {
                return existing
            }
            let space = Space(name: trimmedName)
            try space.insert(db)
            return space
        }
    }

    public func spaces() throws -> [Space] {
        try dbQueue.read { db in
            try Space.order(Column("name")).fetchAll(db)
        }
    }

    public func space(named: String) throws -> Space? {
        let trimmedName = named.trimmingCharacters(in: .whitespaces)
        return try dbQueue.read { db in
            try Space.fetchOne(db,
                sql: "SELECT * FROM space WHERE LOWER(name) = LOWER(?)", arguments: [trimmedName])
        }
    }

    public func spacesMatching(prefix: String) throws -> [Space] {
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespaces)
        return try dbQueue.read { db in
            try Space.fetchAll(db,
                sql: "SELECT * FROM space WHERE LOWER(name) LIKE LOWER(?) ORDER BY name",
                arguments: ["\(trimmedPrefix)%"])
        }
    }

    public func setSpace(noteID: String, spaceID: String?) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE note SET spaceId = ? WHERE id = ?", arguments: [spaceID, noteID])
        }
    }

    public func deleteSpace(id: String) throws {
        try dbQueue.write { db in
            // Null out spaceId for all notes in this space
            try db.execute(sql: "UPDATE note SET spaceId = NULL WHERE spaceId = ?", arguments: [id])
            // Delete the space
            try Space.deleteOne(db, key: id)
        }
    }

    // MARK: - Tags

    public func setTags(noteID: String, names: [String]) throws {
        try dbQueue.write { db in
            // Normalize: lowercase, trim, dedupe, drop empties
            let normalized = Set(
                names
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                    .filter { !$0.isEmpty }
            )

            // Upsert tag rows and collect their IDs
            var tagIds: [String] = []
            for name in normalized {
                let id = UUID().uuidString
                try db.execute(sql: """
                    INSERT INTO tag (id, name) VALUES (?, ?)
                    ON CONFLICT(name) DO UPDATE SET id = id
                    """, arguments: [id, name])
                // Fetch the actual tag id (in case it was a conflict)
                if let existingTag = try Tag.fetchOne(db, sql: "SELECT * FROM tag WHERE name = ?", arguments: [name]) {
                    tagIds.append(existingTag.id)
                }
            }

            // Replace this note's noteTag rows
            try db.execute(sql: "DELETE FROM noteTag WHERE noteId = ?", arguments: [noteID])
            for tagId in tagIds {
                try db.execute(sql: """
                    INSERT INTO noteTag (noteId, tagId) VALUES (?, ?)
                    """, arguments: [noteID, tagId])
            }
        }
    }

    public func tags(noteID: String) throws -> [Tag] {
        try dbQueue.read { db in
            try Tag.fetchAll(db, sql: """
                SELECT t.* FROM tag t
                JOIN noteTag nt ON nt.tagId = t.id
                WHERE nt.noteId = ?
                ORDER BY t.name
                """, arguments: [noteID])
        }
    }

    public func allTags() throws -> [Tag] {
        try dbQueue.read { db in
            try Tag.order(Column("name")).fetchAll(db)
        }
    }

    public func noteIDs(withTag name: String) throws -> [String] {
        let normalizedName = name.trimmingCharacters(in: .whitespaces).lowercased()
        return try dbQueue.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT nt.noteId FROM noteTag nt
                JOIN tag t ON t.id = nt.tagId
                WHERE LOWER(t.name) = LOWER(?)
                """, arguments: [normalizedName])
        }
    }

    // MARK: - Links

    public func link(from: String, to: String, kind: LinkKind) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO noteLink (fromNoteId, toNoteId, kind) VALUES (?, ?, ?)
                ON CONFLICT(fromNoteId, toNoteId, kind) DO NOTHING
                """, arguments: [from, to, kind.rawValue])
        }
    }

    public func unlink(from: String, to: String, kind: LinkKind) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                DELETE FROM noteLink WHERE fromNoteId = ? AND toNoteId = ? AND kind = ?
                """, arguments: [from, to, kind.rawValue])
        }
    }

    public func links(forNoteID: String) throws -> [NoteLink] {
        try dbQueue.read { db in
            try NoteLink.fetchAll(db, sql: """
                SELECT * FROM noteLink WHERE fromNoteId = ? OR toNoteId = ?
                """, arguments: [forNoteID, forNoteID])
        }
    }

    public func linkedNotes(forNoteID: String, kind: LinkKind? = nil) throws -> [Note] {
        try dbQueue.read { db in
            if let kind = kind {
                return try Note.fetchAll(db, sql: """
                    SELECT DISTINCT n.* FROM note n
                    WHERE n.id IN (
                        SELECT toNoteId FROM noteLink WHERE fromNoteId = ? AND kind = ?
                        UNION
                        SELECT fromNoteId FROM noteLink WHERE toNoteId = ? AND kind = ?
                    )
                    ORDER BY n.updatedAt DESC
                    """, arguments: [forNoteID, kind.rawValue, forNoteID, kind.rawValue])
            } else {
                return try Note.fetchAll(db, sql: """
                    SELECT DISTINCT n.* FROM note n
                    WHERE n.id IN (
                        SELECT toNoteId FROM noteLink WHERE fromNoteId = ?
                        UNION
                        SELECT fromNoteId FROM noteLink WHERE toNoteId = ?
                    )
                    ORDER BY n.updatedAt DESC
                    """, arguments: [forNoteID, forNoteID])
            }
        }
    }
}
