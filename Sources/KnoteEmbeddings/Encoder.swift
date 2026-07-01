import Foundation

/// Whether text is being embedded as a search query or a stored note.
/// Asymmetric models (e.g. BGE) prepend an instruction to queries only.
public enum EmbedKind: Sendable {
    case query
    case document
}

/// Produces a fixed-dimension vector for a piece of text. The seam that lets us
/// swap encoders without touching the index or search (ARCHITECTURE.md §7).
///
/// The `id` is stamped into each stored embedding so switching encoders is a
/// background re-index, not a migration.
public protocol Encoder: AnyObject, Sendable {
    var id: String { get }
    var dimension: Int { get }
    func embed(_ text: String, kind: EmbedKind) -> [Float]?
}
