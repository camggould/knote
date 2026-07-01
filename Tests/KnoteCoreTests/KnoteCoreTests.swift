import XCTest
@testable import KnoteCore

final class KnoteCoreTests: XCTestCase {
    func testCreateAndFetch() throws {
        let store = try NoteStore(inMemory: true)
        let note = try store.create(body: "Buy milk\nand eggs")
        XCTAssertEqual(note.title, "Buy milk")
        let fetched = try store.fetch(id: note.id)
        XCTAssertEqual(fetched?.body, "Buy milk\nand eggs")
    }

    func testDeleteCascades() throws {
        let store = try NoteStore(inMemory: true)
        let note = try store.create(body: "temporary")
        try store.saveEmbedding(noteID: note.id, model: "t", vector: [1, 0, 0])
        try store.delete(id: note.id)
        XCTAssertNil(try store.fetch(id: note.id))
        XCTAssertTrue(try store.loadEmbeddings(model: "t").isEmpty)
    }

    func testLexicalSearchFindsNote() throws {
        let store = try NoteStore(inMemory: true)
        _ = try store.create(body: "Meeting notes about the quarterly budget")
        _ = try store.create(body: "Grocery list")
        let hits = try store.lexicalSearch("budget", limit: 10)
        XCTAssertEqual(hits.count, 1)
    }

    func testEmbeddingRoundTrip() throws {
        let store = try NoteStore(inMemory: true)
        let note = try store.create(body: "x")
        try store.saveEmbedding(noteID: note.id, model: "m", vector: [0.1, 0.2, 0.3])
        let loaded = try store.loadEmbeddings(model: "m")
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].vector, [0.1, 0.2, 0.3])
    }

    func testFTSPattern() {
        XCTAssertEqual(NoteStore.ftsPattern("hello world"), "hello* OR world*")
        XCTAssertEqual(NoteStore.ftsPattern("a"), "") // too short
    }
}
