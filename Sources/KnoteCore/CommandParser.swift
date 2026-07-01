import Foundation

/// Structured representation of the user's input in the knote command bar.
public enum Command: Equatable {
    case search(String)
    case compose(String)                                    // /n <body>
    case createSpace(String)                                // /s <name>
    case composeInSpace(space: String, body: String)        // /ns <space> <body>
    case searchInSpace(space: String, query: String)        // /ss <space> <query>
}

/// Stateless parser for the knote command bar. All command prefixes are matched
/// case-insensitively; space names and body text retain their original casing.
public enum CommandParser {

    /// Parse raw text into a structured Command.
    public static func parse(_ input: String) -> Command {
        let lower = input.lowercased()

        // /n — compose note.
        // Check before /ns: "/n " ≠ "/ns" so no collision, but explicit order is clear.
        if lower == "/n" || lower.hasPrefix("/n ") || lower.hasPrefix("/n\n") {
            var rest = String(input.dropFirst(2))
            if rest.hasPrefix(" ") || rest.hasPrefix("\n") { rest.removeFirst() }
            return .compose(rest.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // /ns — compose in space
        if lower.hasPrefix("/ns ") {
            let rest = String(input.dropFirst(4))
            let (space, body) = splitFirstToken(rest)
            return .composeInSpace(space: space, body: body)
        }
        if lower == "/ns" {
            return .composeInSpace(space: "", body: "")
        }

        // /ss — search in space (checked before /s to avoid "/ss " matching "/s ")
        if lower.hasPrefix("/ss ") {
            let rest = String(input.dropFirst(4))
            let (space, query) = splitFirstToken(rest)
            return .searchInSpace(space: space, query: query)
        }
        if lower == "/ss" {
            return .searchInSpace(space: "", query: "")
        }

        // /s — create space
        if lower.hasPrefix("/s ") {
            let name = String(input.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            return .createSpace(name)
        }
        if lower == "/s" {
            return .createSpace("")
        }

        return .search(input)
    }

    /// Returns the partial space-name token being typed when the user is in the
    /// middle of `/ns <partial>` or `/ss <partial>` and has NOT yet typed the
    /// space character that terminates the space-name token. Returns nil in all
    /// other cases (command not recognised, token already complete, or no token).
    public static func spacePrefixBeingTyped(_ input: String) -> String? {
        let lower = input.lowercased()
        let rest: String
        if lower.hasPrefix("/ns ") {
            rest = String(input.dropFirst(4))
        } else if lower.hasPrefix("/ss ") {
            rest = String(input.dropFirst(4))
        } else {
            return nil
        }
        // A space anywhere in `rest` means the token has been terminated already.
        guard !rest.isEmpty, !rest.contains(" ") else { return nil }
        return rest
    }

    // MARK: - Private helpers

    /// Split `text` on the first whitespace into (firstToken, remainder), trimming
    /// the remainder. Returns ("", "") when `text` is empty.
    private static func splitFirstToken(_ text: String) -> (first: String, rest: String) {
        let parts = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard !parts.isEmpty else { return ("", "") }
        let first = String(parts[0])
        let rest = parts.count > 1
            ? String(parts[1]).trimmingCharacters(in: .whitespaces)
            : ""
        return (first, rest)
    }
}
