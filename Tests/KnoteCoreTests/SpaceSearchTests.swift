import XCTest
@testable import KnoteCore
import KnoteEmbeddings
import KnoteVector

final class SpaceSearchTests: XCTestCase {

    // MARK: - setSpace gives note the right spaceId

    func testNoteCaptureedViaSetSpaceHasCorrectSpaceId() throws {
        let store = try NoteStore(inMemory: true)
        let space = try store.createSpace(name: "Work")
        let note = try store.create(body: "Quarterly review")
        try store.setSpace(noteID: note.id, spaceID: space.id)

        let fetched = try store.fetch(id: note.id)
        XCTAssertEqual(fetched?.spaceId, space.id)
    }

    func testNoteWithNoSpaceHasNilSpaceId() throws {
        let store = try NoteStore(inMemory: true)
        let note = try store.create(body: "Unscoped note")
        let fetched = try store.fetch(id: note.id)
        XCTAssertNil(fetched?.spaceId)
    }

    // MARK: - Scoped search filters to space

    func testScopedSearchReturnsOnlyNotesInSpace() throws {
        let store = try NoteStore(inMemory: true)
        let encoder = StubEncoder()
        let index = StubIndex()
        let svc = SearchService(store: store, encoder: encoder, index: index)

        let spaceA = try store.createSpace(name: "Alpha")
        let spaceB = try store.createSpace(name: "Beta")

        let noteA1 = try store.create(body: "Alpha quarterly budget")
        let noteA2 = try store.create(body: "Alpha project plan")
        let noteB1 = try store.create(body: "Beta quarterly report")

        try store.setSpace(noteID: noteA1.id, spaceID: spaceA.id)
        try store.setSpace(noteID: noteA2.id, spaceID: spaceA.id)
        try store.setSpace(noteID: noteB1.id, spaceID: spaceB.id)

        let results = svc.search("quarterly", spaceID: spaceA.id)
        let ids = Set(results.map { $0.note.id })
        XCTAssert(ids.contains(noteA1.id), "Should find Alpha's quarterly note")
        XCTAssertFalse(ids.contains(noteB1.id), "Should not find Beta's note")
        XCTAssertFalse(ids.contains(noteA2.id), "Alpha project plan doesn't match 'quarterly'")
    }

    func testScopedSearchWithEmptyQueryReturnsSpaceRecents() throws {
        let store = try NoteStore(inMemory: true)
        let encoder = StubEncoder()
        let index = StubIndex()
        let svc = SearchService(store: store, encoder: encoder, index: index)

        let spaceA = try store.createSpace(name: "Alpha")
        let noteA = try store.create(body: "Note in Alpha")
        let noteU = try store.create(body: "Unscoped note")
        try store.setSpace(noteID: noteA.id, spaceID: spaceA.id)

        let results = svc.search("", spaceID: spaceA.id)
        let ids = Set(results.map { $0.note.id })
        XCTAssert(ids.contains(noteA.id))
        XCTAssertFalse(ids.contains(noteU.id))
    }

    // MARK: - Scoped recents

    func testScopedRecentsReturnsOnlySpaceNotes() throws {
        let store = try NoteStore(inMemory: true)
        let encoder = StubEncoder()
        let index = StubIndex()
        let svc = SearchService(store: store, encoder: encoder, index: index)

        let spaceA = try store.createSpace(name: "Alpha")
        let spaceB = try store.createSpace(name: "Beta")

        let noteA = try store.create(body: "Alpha note")
        let noteB = try store.create(body: "Beta note")
        let noteU = try store.create(body: "Unscoped note")

        try store.setSpace(noteID: noteA.id, spaceID: spaceA.id)
        try store.setSpace(noteID: noteB.id, spaceID: spaceB.id)

        let recentsA = svc.recents(spaceID: spaceA.id)
        let idsA = Set(recentsA.map { $0.note.id })
        XCTAssertEqual(recentsA.count, 1)
        XCTAssert(idsA.contains(noteA.id))
        XCTAssertFalse(idsA.contains(noteB.id))
        XCTAssertFalse(idsA.contains(noteU.id))
    }

    func testScopedRecentsNilSpaceIDReturnsAll() throws {
        let store = try NoteStore(inMemory: true)
        let encoder = StubEncoder()
        let index = StubIndex()
        let svc = SearchService(store: store, encoder: encoder, index: index)

        let space = try store.createSpace(name: "Work")
        let note1 = try store.create(body: "First")
        let note2 = try store.create(body: "Second")
        try store.setSpace(noteID: note1.id, spaceID: space.id)

        let all = svc.recents(spaceID: nil)
        let ids = Set(all.map { $0.note.id })
        XCTAssert(ids.contains(note1.id))
        XCTAssert(ids.contains(note2.id))
    }

    func testScopedSearchNilSpaceIDIsGlobal() throws {
        let store = try NoteStore(inMemory: true)
        let encoder = StubEncoder()
        let index = StubIndex()
        let svc = SearchService(store: store, encoder: encoder, index: index)

        let space = try store.createSpace(name: "Work")
        let noteA = try store.create(body: "Work quarterly budget")
        let noteB = try store.create(body: "Personal quarterly review")
        try store.setSpace(noteID: noteA.id, spaceID: space.id)

        let results = svc.search("quarterly", spaceID: nil)
        let ids = Set(results.map { $0.note.id })
        XCTAssert(ids.contains(noteA.id))
        XCTAssert(ids.contains(noteB.id))
    }

    func testTwoSpacesNoOverlap() throws {
        let store = try NoteStore(inMemory: true)
        let encoder = StubEncoder()
        let index = StubIndex()
        let svc = SearchService(store: store, encoder: encoder, index: index)

        let spaceA = try store.createSpace(name: "Alpha")
        let spaceB = try store.createSpace(name: "Beta")

        let noteA = try store.create(body: "Alpha only")
        let noteB = try store.create(body: "Beta only")
        try store.setSpace(noteID: noteA.id, spaceID: spaceA.id)
        try store.setSpace(noteID: noteB.id, spaceID: spaceB.id)

        let recA = svc.recents(spaceID: spaceA.id)
        let recB = svc.recents(spaceID: spaceB.id)

        XCTAssertEqual(recA.count, 1)
        XCTAssertEqual(recA[0].note.id, noteA.id)
        XCTAssertEqual(recB.count, 1)
        XCTAssertEqual(recB[0].note.id, noteB.id)
    }
}

// MARK: - Test doubles

private final class StubEncoder: Encoder, @unchecked Sendable {
    let id = "stub.v1"
    let dimension = 1
    func embed(_ text: String, kind: EmbedKind) -> [Float]? { nil }
}

private final class StubIndex: VectorIndex {
    var count: Int { 0 }
    func search(_ query: [Float], k: Int) -> [(id: String, score: Float)] { [] }
    func upsert(id: String, vector: [Float]) {}
    func remove(id: String) {}
}
