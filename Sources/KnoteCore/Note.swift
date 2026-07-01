import Foundation
import GRDB

/// A single note. `title` is derived from the first non-empty line of `body`.
public struct Note: Identifiable, Equatable, Codable, Sendable,
                     FetchableRecord, PersistableRecord {
    public var id: String
    public var body: String
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var spaceId: String?

    public static let databaseTableName = "note"

    public init(id: String = UUID().uuidString,
                body: String,
                createdAt: Date = Date(),
                updatedAt: Date = Date(),
                spaceId: String? = nil) {
        self.id = id
        self.body = body
        self.title = Note.deriveTitle(from: body)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.spaceId = spaceId
    }

    public static func deriveTitle(from body: String) -> String {
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return String(t.prefix(120)) }
        }
        return "Untitled"
    }

    /// The tag pattern: `#` then a word of [A-Za-z0-9_] with optional internal
    /// hyphens (e.g. `#multi-word-tag`), but no leading/trailing hyphen.
    public static let tagPattern = "#([A-Za-z0-9_]+(?:-[A-Za-z0-9_]+)*)"

    /// Extract tags from body text. Returns lowercased, de-duplicated names (no
    /// `#`). Ignores a lone `#`.
    public static func extractTags(from body: String) -> [String] {
        var tags = Set<String>()
        let pattern = try! NSRegularExpression(pattern: tagPattern, options: [])
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        let matches = pattern.matches(in: body, options: [], range: range)
        for match in matches {
            if let range = Range(match.range(at: 1), in: body) {
                let tagName = String(body[range]).lowercased()
                tags.insert(tagName)
            }
        }
        return Array(tags).sorted()
    }
}
