import XCTest
@testable import KnoteCore
import KnoteEmbeddings
import KnoteVector

final class LinkFeatureTests: XCTestCase {

    // MARK: - SearchResult.linkCount via recents()

    func testRecentsReflectsLinkCountOnBothNotes() throws {
        let store = try NoteStore(inMemory: true)
        let svc = SearchService(store: store, encoder: LinkStubEncoder(), index: LinkStubIndex())

        let note1 = try store.create(body: "Question note")
        let note2 = try store.create(body: "Answer note")
        try store.link(from: note2.id, to: note1.id, kind: .answers)

        let recents = svc.recents()
        let r1 = recents.first { $0.note.id == note1.id }
        let r2 = recents.first { $0.note.id == note2.id }

        XCTAssertNotNil(r1, "note1 should appear in recents")
        XCTAssertNotNil(r2, "note2 should appear in recents")
        XCTAssertGreaterThanOrEqual(r1!.linkCount, 1, "note1 has a link and should show linkCount >= 1")
        XCTAssertGreaterThanOrEqual(r2!.linkCount, 1, "note2 has a link and should show linkCount >= 1")
    }

    func testUnlinkedNoteHasZeroLinkCountInRecents() throws {
        let store = try NoteStore(inMemory: true)
        let svc = SearchService(store: store, encoder: LinkStubEncoder(), index: LinkStubIndex())

        _ = try store.create(body: "Standalone note with no links")

        let recents = svc.recents()
        XCTAssertEqual(recents.count, 1)
        XCTAssertEqual(recents[0].linkCount, 0)
    }

    // MARK: - SearchResult.linkCount via search()

    func testSearchReflectsLinkCountOnLinkedNotes() throws {
        let store = try NoteStore(inMemory: true)
        let svc = SearchService(store: store, encoder: LinkStubEncoder(), index: LinkStubIndex())

        let note1 = try store.create(body: "Linked question content")
        let note2 = try store.create(body: "Linked answer content")
        try store.link(from: note2.id, to: note1.id, kind: .answers)

        let results = svc.search("Linked")
        let r1 = results.first { $0.note.id == note1.id }
        let r2 = results.first { $0.note.id == note2.id }

        XCTAssertNotNil(r1)
        XCTAssertNotNil(r2)
        XCTAssertGreaterThanOrEqual(r1!.linkCount, 1)
        XCTAssertGreaterThanOrEqual(r2!.linkCount, 1)
    }

    func testSearchUnlinkedNoteHasZeroLinkCount() throws {
        let store = try NoteStore(inMemory: true)
        let svc = SearchService(store: store, encoder: LinkStubEncoder(), index: LinkStubIndex())

        _ = try store.create(body: "Standalone content with no links")

        let results = svc.search("Standalone")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].linkCount, 0)
    }

    // MARK: - linkCount default

    func testSearchResultDefaultLinkCountIsZero() {
        let note = Note(body: "Test note")
        let result = SearchResult(note: note, score: 1.0)
        XCTAssertEqual(result.linkCount, 0)
    }

    func testSearchResultExplicitLinkCount() {
        let note = Note(body: "Test note")
        let result = SearchResult(note: note, score: 1.0, tags: [], linkCount: 3)
        XCTAssertEqual(result.linkCount, 3)
    }
}

// MARK: - Test doubles

private final class LinkStubEncoder: Encoder, @unchecked Sendable {
    let id = "stub.link.v1"
    let dimension = 1
    func embed(_ text: String, kind: EmbedKind) -> [Float]? { nil }
}

private final class LinkStubIndex: VectorIndex {
    var count: Int { 0 }
    func search(_ query: [Float], k: Int) -> [(id: String, score: Float)] { [] }
    func upsert(id: String, vector: [Float]) {}
    func remove(id: String) {}
}
