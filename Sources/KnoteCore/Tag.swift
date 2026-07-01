import Foundation
import GRDB

/// A tag for organizing and categorizing notes (stored lowercase).
public struct Tag: Identifiable, Equatable, Codable, Sendable,
                   FetchableRecord, PersistableRecord {
    public var id: String
    public var name: String  // stored lowercase

    public static let databaseTableName = "tag"

    public init(id: String = UUID().uuidString, name: String) {
        self.id = id
        self.name = name
    }
}
