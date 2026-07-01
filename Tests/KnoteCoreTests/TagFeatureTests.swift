import XCTest
@testable import KnoteCore

final class TagFeatureTests: XCTestCase {
    // MARK: - Tag Extraction Tests

    func testExtractTagsBasic() throws {
        let body = "Plan #Work and #work-ish #idea"
        let tags = Note.extractTags(from: body)
        XCTAssertEqual(Set(tags), ["work", "idea"])
    }

    func testExtractTagsIgnoresHashWithoutWord() throws {
        let body = "Price is # dollars"
        let tags = Note.extractTags(from: body)
        XCTAssertTrue(tags.isEmpty)
    }

    func testExtractTagsCaseSensitivity() throws {
        let body = "This #Work and #WORK and #work"
        let tags = Note.extractTags(from: body)
        // Should be lowercased and deduplicated
        XCTAssertEqual(Set(tags), ["work"])
    }

    func testExtractTagsWithUnderscores() throws {
        let body = "Label #my_task #project_name #tag"
        let tags = Note.extractTags(from: body)
        XCTAssertEqual(Set(tags), ["my_task", "project_name", "tag"])
    }

    func testExtractTagsWithNumbers() throws {
        let body = "Release #v1 #phase2 #sprint99"
        let tags = Note.extractTags(from: body)
        XCTAssertEqual(Set(tags), ["v1", "phase2", "sprint99"])
    }

    func testExtractTagsEmpty() throws {
        let body = "No tags here"
        let tags = Note.extractTags(from: body)
        XCTAssertTrue(tags.isEmpty)
    }

    func testExtractTagsOnlyHash() throws {
        let body = "Just a # symbol"
        let tags = Note.extractTags(from: body)
        XCTAssertTrue(tags.isEmpty)
    }

    // MARK: - Create Note with Tags

    func testCreateNoteExtractsAndStoresTags() throws {
        let store = try NoteStore(inMemory: true)
        let note = try store.create(body: "Meeting #work #urgent")
        let tags = try store.tags(noteID: note.id)
        let tagNames = Set(tags.map { $0.name })
        XCTAssertEqual(tagNames, ["work", "urgent"])
    }

    func testCreateNoteWithNoTags() throws {
        let store = try NoteStore(inMemory: true)
        let note = try store.create(body: "Plain note")
        let tags = try store.tags(noteID: note.id)
        XCTAssertTrue(tags.isEmpty)
    }

    func testCreateNoteWithDuplicateTags() throws {
        let store = try NoteStore(inMemory: true)
        let note = try store.create(body: "#work is #work related")
        let tags = try store.tags(noteID: note.id)
        XCTAssertEqual(tags.count, 1)
        XCTAssertEqual(tags[0].name, "work")
    }

    // MARK: - Update Note Tags

    func testUpdateNoteSyncsNewTags() throws {
        let store = try NoteStore(inMemory: true)
        let note = try store.create(body: "Initial note")
        var tags = try store.tags(noteID: note.id)
        XCTAssertTrue(tags.isEmpty)

        let updated = try store.update(id: note.id, body: "Updated #project #review")
        XCTAssertNotNil(updated)
        tags = try store.tags(noteID: note.id)
        let tagNames = Set(tags.map { $0.name })
        XCTAssertEqual(tagNames, ["project", "review"])
    }

    func testUpdateNoteReplacesTags() throws {
        let store = try NoteStore(inMemory: true)
        let note = try store.create(body: "Note #old #deprecated")
        var tags = try store.tags(noteID: note.id)
        XCTAssertEqual(tags.count, 2)

        _ = try store.update(id: note.id, body: "Updated #new")
        tags = try store.tags(noteID: note.id)
        let tagNames = Set(tags.map { $0.name })
        XCTAssertEqual(tagNames, ["new"])
    }

    func testUpdateNoteRemovesAllTags() throws {
        let store = try NoteStore(inMemory: true)
        let note = try store.create(body: "Tagged #important #urgent")
        var tags = try store.tags(noteID: note.id)
        XCTAssertEqual(tags.count, 2)

        _ = try store.update(id: note.id, body: "Untagged content")
        tags = try store.tags(noteID: note.id)
        XCTAssertTrue(tags.isEmpty)
    }

    // MARK: - Tag Search

    func testSearchByTagOnly() throws {
        let store = try NoteStore(inMemory: true)
        let note1 = try store.create(body: "Project #work")
        let note2 = try store.create(body: "Hobby #personal")
        let note3 = try store.create(body: "Task #work #urgent")

        let workNoteIDs = try store.noteIDs(withTag: "work")
        XCTAssertEqual(workNoteIDs.count, 2)
        XCTAssert(workNoteIDs.contains(note1.id))
        XCTAssert(workNoteIDs.contains(note3.id))
        XCTAssertFalse(workNoteIDs.contains(note2.id))
    }

    func testSearchByMultipleTags() throws {
        let store = try NoteStore(inMemory: true)
        let note1 = try store.create(body: "Task #work #urgent")
        _ = try store.create(body: "Meeting #work")
        _ = try store.create(body: "Call #urgent")

        let workIDs = try store.noteIDs(withTag: "work")
        let urgentIDs = try store.noteIDs(withTag: "urgent")

        // Intersection: only notes with both tags
        let intersection = Set(workIDs).intersection(Set(urgentIDs))
        XCTAssertEqual(intersection.count, 1)
        XCTAssert(intersection.contains(note1.id))
    }

    // MARK: - SearchResult Tags

    func testSearchResultIncludesTags() throws {
        let note = Note(body: "Test")
        let result = SearchResult(note: note, score: 1.0, tags: ["work", "urgent"])
        XCTAssertEqual(result.tags.count, 2)
        XCTAssert(result.tags.contains("work"))
        XCTAssert(result.tags.contains("urgent"))
    }

    func testSearchResultDefaultNoTags() throws {
        let note = Note(body: "Test")
        let result = SearchResult(note: note, score: 1.0)
        XCTAssertTrue(result.tags.isEmpty)
    }

    // MARK: - allTags

    func testAllTagsReturnsAllUniqueTags() throws {
        let store = try NoteStore(inMemory: true)
        _ = try store.create(body: "Note one #alpha #beta")
        _ = try store.create(body: "Note two #beta #gamma")
        let tags = try store.allTags()
        let names = tags.map { $0.name }
        XCTAssertEqual(Set(names), ["alpha", "beta", "gamma"])
    }

    func testAllTagsAreOrderedByName() throws {
        let store = try NoteStore(inMemory: true)
        _ = try store.create(body: "Note #zebra #apple #mango")
        let tags = try store.allTags()
        let names = tags.map { $0.name }
        XCTAssertEqual(names, names.sorted())
    }

    func testAllTagsEmptyStore() throws {
        let store = try NoteStore(inMemory: true)
        let tags = try store.allTags()
        XCTAssertTrue(tags.isEmpty)
    }
}
