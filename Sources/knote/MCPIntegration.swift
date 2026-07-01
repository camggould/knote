import AppKit
import Foundation
import KnoteCore

/// Helpers for registering the bundled `knote-mcp` server with AI assistants.
enum MCPIntegration {

    /// Absolute path to the bundled MCP helper binary.
    static var helperPath: String {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/knote-mcp")
            .path
    }

    // MARK: - Outcome

    enum Outcome {
        case added
        case alreadyPresent
        /// Claude CLI not found or returned a non-zero exit code.
        /// The manual command has been copied to the pasteboard.
        case needsManual(String)
        case failed(String)
    }

    // MARK: - Actions

    /// Appends the knote MCP server entry to `~/.codex/config.toml`.
    static func addToCodex() -> Outcome {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".codex")
        let configURL = dir.appendingPathComponent("config.toml")

        let existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let result = CodexConfig.appending(command: helperPath, to: existing)

        guard result.added else { return .alreadyPresent }

        do {
            try FileManager.default.createDirectory(at: dir,
                                                    withIntermediateDirectories: true)
            try result.content.write(to: configURL, atomically: true, encoding: .utf8)
            return .added
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Runs `claude mcp add` through a login shell so the user's PATH is available.
    ///
    /// On success returns `.added`. If the CLI is not found or exits non-zero,
    /// the manual command is copied to the pasteboard and `.needsManual` is returned.
    static func addToClaudeCode() -> Outcome {
        let command = "claude mcp add knote \"\(helperPath)\" -s user"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]

        // Suppress stdout/stderr so the output doesn't appear in Console.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return .added
            }
        } catch { /* fall through to needsManual */ }

        copyToPasteboard(command)
        return .needsManual(command)
    }

    /// Puts the TOML snippet for manual pasting into `~/.codex/config.toml`.
    static func copyCodexSnippet() {
        let snippet = "[mcp_servers.knote]\ncommand = \"\(helperPath)\"\nargs = []\n"
        copyToPasteboard(snippet)
    }

    // MARK: - Private

    private static func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
