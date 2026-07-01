import Foundation
import GRDB

/// The type of link between two notes.
public enum LinkKind: String, Codable, Sendable {
    case answers
    case related
}

/// A directional link from one note to another.
public struct NoteLink: Equatable, Codable, Sendable,
                        FetchableRecord, PersistableRecord {
    public var fromNoteId: String
    public var toNoteId: String
    public var kind: String  // stored as "answers" or "related"

    public static let databaseTableName = "noteLink"

    public init(fromNoteId: String, toNoteId: String, kind: String) {
        self.fromNoteId = fromNoteId
        self.toNoteId = toNoteId
        self.kind = kind
    }
}
