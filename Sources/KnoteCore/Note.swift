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

    public static let databaseTableName = "note"

    public init(id: String = UUID().uuidString,
                body: String,
                createdAt: Date = Date(),
                updatedAt: Date = Date()) {
        self.id = id
        self.body = body
        self.title = Note.deriveTitle(from: body)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func deriveTitle(from body: String) -> String {
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return String(t.prefix(120)) }
        }
        return "Untitled"
    }
}
