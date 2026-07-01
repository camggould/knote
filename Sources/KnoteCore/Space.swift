import Foundation
import GRDB

/// A workspace or collection for organizing notes.
public struct Space: Identifiable, Equatable, Codable, Sendable,
                     FetchableRecord, PersistableRecord {
    public var id: String
    public var name: String
    public var createdAt: Date

    public static let databaseTableName = "space"

    public init(id: String = UUID().uuidString,
                name: String,
                createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}
