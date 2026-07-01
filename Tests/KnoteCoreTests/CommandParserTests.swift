import XCTest
@testable import KnoteCore

final class CommandParserTests: XCTestCase {

    // MARK: - /n compose

    func testParseComposeSlashN() {
        XCTAssertEqual(CommandParser.parse("/n"), .compose(""))
    }

    func testParseComposeSlashNWithSpace() {
        XCTAssertEqual(CommandParser.parse("/n "), .compose(""))
    }

    func testParseComposeSlashNWithBody() {
        XCTAssertEqual(CommandParser.parse("/n hello world"), .compose("hello world"))
    }

    func testParseComposeSlashNCaseInsensitive() {
        XCTAssertEqual(CommandParser.parse("/N Hello"), .compose("Hello"))
    }

    func testParseComposeTrimsBody() {
        XCTAssertEqual(CommandParser.parse("/n  trimmed  "), .compose("trimmed"))
    }

    // MARK: - /s create space

    func testParseCreateSpace() {
        XCTAssertEqual(CommandParser.parse("/s Work"), .createSpace("Work"))
    }

    func testParseCreateSpaceTrimsName() {
        XCTAssertEqual(CommandParser.parse("/s  Work  "), .createSpace("Work"))
    }

    func testParseCreateSpaceCaseInsensitiveCommand() {
        XCTAssertEqual(CommandParser.parse("/S Personal"), .createSpace("Personal"))
    }

    func testParseCreateSpaceAloneReturnsEmpty() {
        XCTAssertEqual(CommandParser.parse("/s"), .createSpace(""))
    }

    // MARK: - /ns compose in space

    func testParseComposeInSpaceWithBody() {
        XCTAssertEqual(
            CommandParser.parse("/ns Work Write a proposal"),
            .composeInSpace(space: "Work", body: "Write a proposal")
        )
    }

    func testParseComposeInSpaceNoBody() {
        XCTAssertEqual(
            CommandParser.parse("/ns Work"),
            .composeInSpace(space: "Work", body: "")
        )
    }

    func testParseComposeInSpaceWithTrailingSpaceNoBody() {
        XCTAssertEqual(
            CommandParser.parse("/ns Work "),
            .composeInSpace(space: "Work", body: "")
        )
    }

    func testParseComposeInSpaceCaseInsensitiveCommand() {
        XCTAssertEqual(
            CommandParser.parse("/NS Work body"),
            .composeInSpace(space: "Work", body: "body")
        )
    }

    func testParseComposeInSpaceAlone() {
        XCTAssertEqual(CommandParser.parse("/ns"), .composeInSpace(space: "", body: ""))
    }

    func testParseComposeInSpacePreservesBodyCasing() {
        XCTAssertEqual(
            CommandParser.parse("/ns MySpace Hello World"),
            .composeInSpace(space: "MySpace", body: "Hello World")
        )
    }

    // MARK: - /ss search in space

    func testParseSearchInSpaceWithQuery() {
        XCTAssertEqual(
            CommandParser.parse("/ss Work quarterly"),
            .searchInSpace(space: "Work", query: "quarterly")
        )
    }

    func testParseSearchInSpaceNoQuery() {
        XCTAssertEqual(
            CommandParser.parse("/ss Work"),
            .searchInSpace(space: "Work", query: "")
        )
    }

    func testParseSearchInSpaceAlone() {
        XCTAssertEqual(CommandParser.parse("/ss"), .searchInSpace(space: "", query: ""))
    }

    func testParseSearchInSpaceCaseInsensitiveCommand() {
        XCTAssertEqual(
            CommandParser.parse("/SS Work budget"),
            .searchInSpace(space: "Work", query: "budget")
        )
    }

    // MARK: - Plain search

    func testParsePlainSearch() {
        XCTAssertEqual(CommandParser.parse("hello"), .search("hello"))
    }

    func testParsePlainSearchEmpty() {
        XCTAssertEqual(CommandParser.parse(""), .search(""))
    }

    func testParsePlainSearchWithSlash() {
        XCTAssertEqual(CommandParser.parse("/unknown"), .search("/unknown"))
    }

    func testParsePlainSearchWithHashtag() {
        XCTAssertEqual(CommandParser.parse("#work meeting"), .search("#work meeting"))
    }

    // MARK: - /ns vs /n disambiguation

    func testParseSlashNDoesNotConsumeSlashNS() {
        // "/ns Work" must parse as composeInSpace, not compose
        let result = CommandParser.parse("/ns Work")
        if case .composeInSpace(let space, _) = result {
            XCTAssertEqual(space, "Work")
        } else {
            XCTFail("Expected composeInSpace, got \(result)")
        }
    }

    // MARK: - spacePrefixBeingTyped

    func testSpacePrefixBeingTypedNSPartial() {
        XCTAssertEqual(CommandParser.spacePrefixBeingTyped("/ns wor"), "wor")
    }

    func testSpacePrefixBeingTypedSSPartial() {
        XCTAssertEqual(CommandParser.spacePrefixBeingTyped("/ss per"), "per")
    }

    func testSpacePrefixBeingTypedNilWhenComplete() {
        // Trailing space means the token is done
        XCTAssertNil(CommandParser.spacePrefixBeingTyped("/ns Work "))
    }

    func testSpacePrefixBeingTypedNilWhenBodyFollows() {
        XCTAssertNil(CommandParser.spacePrefixBeingTyped("/ns Work hello"))
    }

    func testSpacePrefixBeingTypedNilForPlainSearch() {
        XCTAssertNil(CommandParser.spacePrefixBeingTyped("hello"))
    }

    func testSpacePrefixBeingTypedNilForComposeCommand() {
        XCTAssertNil(CommandParser.spacePrefixBeingTyped("/n hello"))
    }

    func testSpacePrefixBeingTypedNilWhenEmptyAfterCommand() {
        // "/ns " — command entered but no space name started yet
        XCTAssertNil(CommandParser.spacePrefixBeingTyped("/ns "))
        XCTAssertNil(CommandParser.spacePrefixBeingTyped("/ss "))
    }

    func testSpacePrefixBeingTypedCaseInsensitiveCommand() {
        XCTAssertEqual(CommandParser.spacePrefixBeingTyped("/NS wor"), "wor")
        XCTAssertEqual(CommandParser.spacePrefixBeingTyped("/SS per"), "per")
    }
}
