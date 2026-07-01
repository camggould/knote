import XCTest
import GRDB
@testable import KnoteCore

/// Proves the v0.1.0 → v0.2.0 database upgrade is additive and non-destructive:
/// an existing v1 database keeps all its notes/embeddings/FTS after the v2
/// migration, and gains the new spaces/tags/links schema.
final class UpgradeTests: XCTestCase {
    private func tempDBPath() -> String {
        NSTemporaryDirectory() + "knote-upgrade-\(UUID().uuidString).sqlite"
    }

    func testV1DatabaseUpgradesToV2WithoutDataLoss() throws {
        let path = tempDBPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        // 1. Simulate a v0.1.0 database: migrate ONLY up to "v1".
        let dbQueue = try DatabaseQueue(path: path)
        try NoteStore.makeMigrator().migrate(dbQueue, upTo: "v1")

        // Sanity: the v2 tables/columns do NOT exist yet.
        try dbQueue.read { db in
            XCTAssertFalse(try db.tableExists("space"))
            XCTAssertFalse(try db.columns(in: "note").contains { $0.name == "spaceId" })
        }

        // 2. Insert a note (+ embedding) the way v0.1.0 would have.
        let vector: [Float] = [0.1, 0.2, 0.3]
        let blob = vector.withUnsafeBufferPointer { Data(buffer: $0) }
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO note (id, body, title, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: ["n1", "Remember the milk #home", "Remember the milk", 1000.0, 2000.0])
            try db.execute(sql: """
                INSERT INTO embedding (note_id, model, dim, vector) VALUES (?, ?, ?, ?)
                """, arguments: ["n1", "nl.en.v1", 3, blob])
        }
        // v1 FTS already indexes it.
        try dbQueue.read { db in
            let hits = try Int.fetchOne(db, sql:
                "SELECT count(*) FROM note_fts WHERE note_fts MATCH 'milk'") ?? 0
            XCTAssertEqual(hits, 1)
        }

        // 3. Upgrade: run the full migrator (applies "v2").
        try NoteStore.makeMigrator().migrate(dbQueue)

        // 4. Nothing was lost, and the new schema is present.
        try dbQueue.read { db in
            // Existing note intact.
            let body = try String.fetchOne(db, sql: "SELECT body FROM note WHERE id = 'n1'")
            XCTAssertEqual(body, "Remember the milk #home")
            // Existing embedding intact.
            let embCount = try Int.fetchOne(db, sql:
                "SELECT count(*) FROM embedding WHERE note_id = 'n1'") ?? 0
            XCTAssertEqual(embCount, 1)
            // FTS still works.
            let hits = try Int.fetchOne(db, sql:
                "SELECT count(*) FROM note_fts WHERE note_fts MATCH 'milk'") ?? 0
            XCTAssertEqual(hits, 1)
            // New schema exists.
            XCTAssertTrue(try db.columns(in: "note").contains { $0.name == "spaceId" })
            XCTAssertTrue(try db.tableExists("space"))
            XCTAssertTrue(try db.tableExists("tag"))
            XCTAssertTrue(try db.tableExists("noteTag"))
            XCTAssertTrue(try db.tableExists("noteLink"))
        }
    }

    func testUpgradedDatabaseIsUsableViaNoteStore() throws {
        let path = tempDBPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        // Old v1 db with one note.
        let old = try DatabaseQueue(path: path)
        try NoteStore.makeMigrator().migrate(old, upTo: "v1")
        try old.write { db in
            try db.execute(sql: """
                INSERT INTO note (id, body, title, createdAt, updatedAt)
                VALUES ('old1', 'quarterly budget review', 'quarterly budget review', 1.0, 2.0)
                """)
        }
        try old.close()

        // Open with the real NoteStore (runs v2) and use v2 features on the old note.
        let store = try NoteStore(path: URL(fileURLWithPath: path))
        XCTAssertEqual(try store.fetch(id: "old1")?.body, "quarterly budget review")
        XCTAssertFalse(try store.lexicalSearch("budget", limit: 10).isEmpty)

        let space = try store.createSpace(name: "Finance")
        try store.setSpace(noteID: "old1", spaceID: space.id)
        XCTAssertEqual(try store.fetch(id: "old1")?.spaceId, space.id)

        try store.setTags(noteID: "old1", names: ["finance"])
        XCTAssertEqual(try store.tags(noteID: "old1").map(\.name), ["finance"])
    }

    func testUpgradeBackfillsTagsForPreexistingNotes() throws {
        let path = tempDBPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        // A v1 note whose body has #hashtags — written before tags existed, so
        // it has no tag rows.
        let old = try DatabaseQueue(path: path)
        try NoteStore.makeMigrator().migrate(old, upTo: "v1")
        try old.write { db in
            try db.execute(sql: """
                INSERT INTO note (id, body, title, createdAt, updatedAt)
                VALUES ('old1', 'Plan the offsite #work #travel', 'Plan the offsite', 1.0, 2.0)
                """)
        }
        try old.close()

        // Upgrade → the v3 backfill parses tags from existing bodies.
        let store = try NoteStore(path: URL(fileURLWithPath: path))
        XCTAssertEqual(try store.tags(noteID: "old1").map(\.name).sorted(), ["travel", "work"])
        XCTAssertEqual(try store.noteIDs(withTag: "work"), ["old1"])
    }
}
