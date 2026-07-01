import Foundation

/// Pure, testable helper for reading and updating a Codex config.toml file.
public enum CodexConfig {
    /// Appends a `[mcp_servers.knote]` block to `existing` TOML content.
    ///
    /// - Returns: The updated content and whether a block was actually appended.
    ///   If `existing` already contains `[mcp_servers.knote]`, the original
    ///   string is returned unchanged and `added` is `false`.
    public static func appending(command: String, to existing: String) -> (content: String, added: Bool) {
        guard !existing.contains("[mcp_servers.knote]") else {
            return (existing, false)
        }

        let block = "[mcp_servers.knote]\ncommand = \"\(command)\"\nargs = []\n"

        if existing.isEmpty {
            return (block, true)
        }

        // Trim trailing whitespace/newlines so there's exactly one blank line
        // separating the existing content from the appended block.
        let trimmed = existing.replacingOccurrences(of: "\\s+$", with: "",
                                                     options: .regularExpression)
        return (trimmed + "\n\n" + block, true)
    }
}
