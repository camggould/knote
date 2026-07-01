import XCTest
@testable import KnoteCore

final class CodexConfigTests: XCTestCase {

    // MARK: - Appending to empty input

    func testAppendsToEmpty() {
        let (content, added) = CodexConfig.appending(command: "/usr/local/bin/knote-mcp", to: "")
        XCTAssertTrue(added)
        XCTAssertTrue(content.contains("[mcp_servers.knote]"))
        XCTAssertTrue(content.contains("command = \"/usr/local/bin/knote-mcp\""))
        XCTAssertTrue(content.contains("args = []"))
    }

    func testEmptyInputStartsWithBlock() {
        let (content, _) = CodexConfig.appending(command: "/bin/knote-mcp", to: "")
        XCTAssertTrue(content.hasPrefix("[mcp_servers.knote]"))
    }

    // MARK: - Appending to existing content

    func testAppendsToExistingNonKnoteContent() {
        let existing = "[other_section]\nfoo = \"bar\"\n"
        let (content, added) = CodexConfig.appending(command: "/usr/local/bin/knote-mcp", to: existing)
        XCTAssertTrue(added)
        XCTAssertTrue(content.hasPrefix("[other_section]"),
                      "Original content should precede the appended block")
        XCTAssertTrue(content.contains("[mcp_servers.knote]"))
        XCTAssertTrue(content.contains("command = \"/usr/local/bin/knote-mcp\""))
    }

    func testExactlyOneBlankLineBeforeAppendedBlock() {
        let existing = "[other_section]\nfoo = \"bar\"\n"
        let (content, _) = CodexConfig.appending(command: "/bin/knote-mcp", to: existing)
        // The separator between existing content and new block should be \n\n
        XCTAssertTrue(content.contains("\n\n[mcp_servers.knote]"),
                      "Expected exactly one blank line before the appended block")
    }

    // MARK: - Idempotency

    func testIdempotentWhenBlockAlreadyPresent() {
        let existing = "[mcp_servers.knote]\ncommand = \"/old/path\"\nargs = []\n"
        let (content, added) = CodexConfig.appending(command: "/new/path", to: existing)
        XCTAssertFalse(added)
        XCTAssertEqual(content, existing, "Content must be unchanged when block is already present")
    }

    func testIdempotentPreservesExistingCommand() {
        let existing = "[mcp_servers.knote]\ncommand = \"/original/path\"\nargs = []\n"
        let (content, _) = CodexConfig.appending(command: "/different/path", to: existing)
        XCTAssertTrue(content.contains("/original/path"),
                      "Original command should be preserved")
        XCTAssertFalse(content.contains("/different/path"),
                       "New command must not be inserted when block already present")
    }
}
