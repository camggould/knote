import Foundation

/// A nearest-neighbor index over note embeddings.
///
/// The single seam that lets us swap brute-force for sqlite-vec / HNSW later
/// without touching callers (see ARCHITECTURE.md §6).
public protocol VectorIndex: AnyObject {
    func upsert(id: String, vector: [Float])
    func remove(id: String)
    /// Returns up to `k` ids with the highest cosine similarity to `query`,
    /// score descending. Assumes stored + query vectors are L2-normalized, so
    /// cosine similarity is a plain dot product.
    func search(_ query: [Float], k: Int) -> [(id: String, score: Float)]
    var count: Int { get }
}
