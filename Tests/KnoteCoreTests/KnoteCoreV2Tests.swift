import XCTest
@testable import KnoteCore

final class KnoteCoreV2Tests: XCTestCase {
    // MARK: - Space Tests

    func testCreateSpaceAndFetch() throws {
        let store = try NoteStore(inMemory: true)
        let space = try store.createSpace(name: "Work")
        XCTAssertEqual(space.name, "Work")
        let fetched = try store.space(named: "Work")
        XCTAssertEqual(fetched?.id, space.id)
    }

    func testCreateSpaceCaseInsensitiveUniqueness() throws {
        let store = try NoteStore(inMemory: true)
        let space1 = try store.createSpace(name: "Work")
        let space2 = try store.createSpace(name: "work")  // Different case
        XCTAssertEqual(space1.id, space2.id)  // Should return same space
    }

    func testSpacesOrderedByName() throws {
        let store = try NoteStore(inMemory: true)
        _ = try store.createSpace(name: "Zebra")
        _ = try store.createSpace(name: "Alpha")
        _ = try store.createSpace(name: "Beta")
        let spaces = try store.spaces()
        XCTAssertEqual(spaces.count, 3)
        XCTAssertEqual(spaces[0].name, "Alpha")
        XCTAssertEqual(spaces[1].name, "Beta")
        XCTAssertEqual(spaces[2].name, "Zebra")
    }

    func testSpaceNameTrimming() throws {
        let store = try NoteStore(inMemory: true)
        let space = try store.createSpace(name: "  Work  ")
        XCTAssertEqual(space.name, "Work")
    }

    func testSpacesMatchingPrefix() throws {
        let store = try NoteStore(inMemory: true)
        _ = try store.createSpace(name: "Work")
        _ = try store.createSpace(name: "Workshop")
        _ = try store.createSpace(name: "Personal")
        let matches = try store.spacesMatching(prefix: "Work")
        XCTAssertEqual(matches.count, 2)
        XCTAssert(matches.allSatisfy { $0.name.lowercased().hasPrefix("work") })
    }

    func testSpacesMatchingPrefixCaseInsensitive() throws {
        let store = try NoteStore(inMemory: true)
        _ = try store.createSpace(name: "Work")
        let matches = try store.spacesMatching(prefix: "wor")
        XCTAssertEqual(matches.count, 1)
    }

    func testSetSpaceOnNote() throws {
        let store = try NoteStore(inMemory: true)
        let note = try store.create(body: "Test note")
        let space = try store.createSpace(name: "Work")
        try store.setSpace(noteID: note.id, spaceID: space.id)
        let fetched = try store.fetch(id: note.id)
        XCTAssertEqual(fetched?.spaceId, space.id)
    }

    func testSetSpaceToNil() throws {
        let store = try NoteStore(inMemory: true)
        let note = try store.create(body: "Test note")
        let space = try store.createSpace(name: "Work")
        try store.setSpace(noteID: note.id, spaceID: space.id)
        try store.setSpace(noteID: note.id, spaceID: nil)
        let fetched = try store.fetch(id: note.id)
        XCTAssertNil(fetched?.spaceId)
    }

    func testDeleteSpaceNullsOutMemberNotes() throws {
        let store = try NoteStore(inMemory: true)
        let note1 = try store.create(body: "Note 1")
        let note2 = try store.create(body: "Note 2")
        let space = try store.createSpace(name: "Work")
        try store.setSpace(noteID: note1.id, spaceID: space.id)
        try store.setSpace(noteID: note2.id, spaceID: space.id)
        try store.deleteSpace(id: space.id)
        let fetched1 = try store.fetch(id: note1.id)
        let fetched2 = try store.fetch(id: note2.id)
        XCTAssertNil(fetched1?.spaceId)
        XCTAssertNil(fetched2?.spaceId)
    }

    // MARK: - Tag Tests

    func testSetTagsOnNote() throws {
        let store = try NoteStore(inMemory: true)
        let note = try store.create(body: "Test note")
        try store.setTags(noteID: note.id, names: ["work", "important"])
        let tags = try store.tags(noteID: note.id)
        XCTAssertEqual(tags.count, 2)
        let names = Set(tags.map { $0.name })
        XCTAssert(names.contains("work"))
        XCTAssert(names.contains("important"))
    }

    func testTagsNormalized() throws {
        let store = try NoteStore(inMemory: true)
        let note = try store.create(body: "Test note")
        try store.setTags(noteID: note.id, names: ["  WORK  ", "important"])
        let tags = try store.tags(noteID: note.id)
        XCTAssertEqual(tags.count, 2)
        let names = Set(tags.map { $0.name })
        XCTAssert(names.contains("work"))  // lowercased
        XCTAssert(names.contains("important"))
    }

    func testSetTagsReplaceSemantics() throws {
        let store = try NoteStore(inMemory: true)
        let note = try store.create(body: "Test note")
        try store.setTags(noteID: note.id, names: ["work", "important"])
        var tags = try store.tags(noteID: note.id)
        XCTAssertEqual(tags.count, 2)
        // Replace with different set
        try store.setTags(noteID: note.id, names: ["personal"])
        tags = try store.tags(noteID: note.id)
        XCTAssertEqual(tags.count, 1)
        XCTAssertEqual(tags[0].name, "personal")
    }

    func testSetTagsDropsEmptyStrings() throws {
        let store = try NoteStore(inMemory: true)
        let note = try store.create(body: "Test note")
        try store.setTags(noteID: note.id, names: ["work", "", "  ", "important"])
        let tags = try store.tags(noteID: note.id)
        XCTAssertEqual(tags.count, 2)
    }

    func testSetTagsDeduplicated() throws {
        let store = try NoteStore(inMemory: true)
        let note = try store.create(body: "Test note")
        try store.setTags(noteID: note.id, names: ["work", "WORK", "work"])
        let tags = try store.tags(noteID: note.id)
        XCTAssertEqual(tags.count, 1)
        XCTAssertEqual(tags[0].name, "work")
    }

    func testTagsOrderedByName() throws {
        let store = try NoteStore(inMemory: true)
        let note = try store.create(body: "Test note")
        try store.setTags(noteID: note.id, names: ["zebra", "alpha", "beta"])
        let tags = try store.tags(noteID: note.id)
        XCTAssertEqual(tags[0].name, "alpha")
        XCTAssertEqual(tags[1].name, "beta")
        XCTAssertEqual(tags[2].name, "zebra")
    }

    func testNoteIDsWithTag() throws {
        let store = try NoteStore(inMemory: true)
        let note1 = try store.create(body: "Note 1")
        let note2 = try store.create(body: "Note 2")
        let note3 = try store.create(body: "Note 3")
        try store.setTags(noteID: note1.id, names: ["work"])
        try store.setTags(noteID: note2.id, names: ["work", "urgent"])
        try store.setTags(noteID: note3.id, names: ["personal"])
        let noteIds = try store.noteIDs(withTag: "work")
        XCTAssertEqual(noteIds.count, 2)
        XCTAssert(noteIds.contains(note1.id))
        XCTAssert(noteIds.contains(note2.id))
    }

    func testNoteIDsWithTagCaseInsensitive() throws {
        let store = try NoteStore(inMemory: true)
        let note = try store.create(body: "Note")
        try store.setTags(noteID: note.id, names: ["work"])
        let noteIds = try store.noteIDs(withTag: "WORK")
        XCTAssertEqual(noteIds.count, 1)
        XCTAssertEqual(noteIds[0], note.id)
    }

    // MARK: - Link Tests

    func testLinkNotes() throws {
        let store = try NoteStore(inMemory: true)
        let note1 = try store.create(body: "Question")
        let note2 = try store.create(body: "Answer")
        try store.link(from: note1.id, to: note2.id, kind: .answers)
        let links = try store.links(forNoteID: note1.id)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links[0].fromNoteId, note1.id)
        XCTAssertEqual(links[0].toNoteId, note2.id)
        XCTAssertEqual(links[0].kind, "answers")
    }

    func testLinkIdempotent() throws {
        let store = try NoteStore(inMemory: true)
        let note1 = try store.create(body: "Note 1")
        let note2 = try store.create(body: "Note 2")
        try store.link(from: note1.id, to: note2.id, kind: .answers)
        try store.link(from: note1.id, to: note2.id, kind: .answers)
        let links = try store.links(forNoteID: note1.id)
        XCTAssertEqual(links.count, 1)
    }

    func testLinksFromBothDirections() throws {
        let store = try NoteStore(inMemory: true)
        let note1 = try store.create(body: "Note 1")
        let note2 = try store.create(body: "Note 2")
        try store.link(from: note1.id, to: note2.id, kind: .related)
        // Links should be found from both sides
        let linksFrom1 = try store.links(forNoteID: note1.id)
        let linksFrom2 = try store.links(forNoteID: note2.id)
        XCTAssertEqual(linksFrom1.count, 1)
        XCTAssertEqual(linksFrom2.count, 1)
    }

    func testUnlink() throws {
        let store = try NoteStore(inMemory: true)
        let note1 = try store.create(body: "Note 1")
        let note2 = try store.create(body: "Note 2")
        try store.link(from: note1.id, to: note2.id, kind: .answers)
        try store.unlink(from: note1.id, to: note2.id, kind: .answers)
        let links = try store.links(forNoteID: note1.id)
        XCTAssertTrue(links.isEmpty)
    }

    func testLinkedNotes() throws {
        let store = try NoteStore(inMemory: true)
        let note1 = try store.create(body: "Note 1")
        let note2 = try store.create(body: "Note 2")
        let note3 = try store.create(body: "Note 3")
        try store.link(from: note1.id, to: note2.id, kind: .answers)
        try store.link(from: note1.id, to: note3.id, kind: .related)
        let linked = try store.linkedNotes(forNoteID: note1.id)
        XCTAssertEqual(linked.count, 2)
        let linkedIds = Set(linked.map { $0.id })
        XCTAssert(linkedIds.contains(note2.id))
        XCTAssert(linkedIds.contains(note3.id))
    }

    func testLinkedNotesWithKindFilter() throws {
        let store = try NoteStore(inMemory: true)
        let note1 = try store.create(body: "Note 1")
        let note2 = try store.create(body: "Note 2")
        let note3 = try store.create(body: "Note 3")
        try store.link(from: note1.id, to: note2.id, kind: .answers)
        try store.link(from: note1.id, to: note3.id, kind: .related)
        let answers = try store.linkedNotes(forNoteID: note1.id, kind: .answers)
        XCTAssertEqual(answers.count, 1)
        XCTAssertEqual(answers[0].id, note2.id)
    }

    func testLinkedNotesBidirectional() throws {
        let store = try NoteStore(inMemory: true)
        let note1 = try store.create(body: "Note 1")
        let note2 = try store.create(body: "Note 2")
        try store.link(from: note2.id, to: note1.id, kind: .related)
        let linked = try store.linkedNotes(forNoteID: note1.id)
        XCTAssertEqual(linked.count, 1)
        XCTAssertEqual(linked[0].id, note2.id)
    }

    // MARK: - Cascade Delete Tests

    func testDeleteNoteCascadesNoteLinks() throws {
        let store = try NoteStore(inMemory: true)
        let note1 = try store.create(body: "Note 1")
        let note2 = try store.create(body: "Note 2")
        try store.link(from: note1.id, to: note2.id, kind: .answers)
        try store.delete(id: note1.id)
        let links = try store.links(forNoteID: note2.id)
        XCTAssertTrue(links.isEmpty)
    }

    func testDeleteNoteCascadesNoteTags() throws {
        let store = try NoteStore(inMemory: true)
        let note = try store.create(body: "Note")
        try store.setTags(noteID: note.id, names: ["work", "urgent"])
        try store.delete(id: note.id)
        let tags = try store.tags(noteID: note.id)
        XCTAssertTrue(tags.isEmpty)
    }

    func testDeleteNoteDoesNotDeleteTags() throws {
        let store = try NoteStore(inMemory: true)
        let note1 = try store.create(body: "Note 1")
        let note2 = try store.create(body: "Note 2")
        try store.setTags(noteID: note1.id, names: ["work"])
        try store.setTags(noteID: note2.id, names: ["work"])
        try store.delete(id: note1.id)
        // The tag should still exist and be associated with note2
        let tags = try store.tags(noteID: note2.id)
        XCTAssertEqual(tags.count, 1)
        XCTAssertEqual(tags[0].name, "work")
    }

    // MARK: - Integration Tests

    func testNoteStoreWithSpaceAndTags() throws {
        let store = try NoteStore(inMemory: true)
        let space = try store.createSpace(name: "Work")
        let note = try store.create(body: "Project proposal")
        try store.setSpace(noteID: note.id, spaceID: space.id)
        try store.setTags(noteID: note.id, names: ["urgent", "proposal"])

        let fetched = try store.fetch(id: note.id)
        XCTAssertEqual(fetched?.spaceId, space.id)
        let tags = try store.tags(noteID: note.id)
        XCTAssertEqual(tags.count, 2)
    }

    func testNoteStoreWithLinks() throws {
        let store = try NoteStore(inMemory: true)
        let question = try store.create(body: "What is Swift?")
        let answer = try store.create(body: "Swift is a programming language")
        try store.link(from: question.id, to: answer.id, kind: .answers)

        let linked = try store.linkedNotes(forNoteID: question.id, kind: .answers)
        XCTAssertEqual(linked.count, 1)
        XCTAssertEqual(linked[0].id, answer.id)
    }
}
