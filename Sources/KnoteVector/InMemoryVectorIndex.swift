import Foundation
import Accelerate

/// Brute-force in-memory cosine similarity. Exact, dependency-free, and a few
/// milliseconds even at ~100k notes (ARCHITECTURE.md §6). Thread-safe.
public final class InMemoryVectorIndex: VectorIndex {
    private var vectors: [String: [Float]] = [:]
    private let lock = NSLock()

    public init() {}

    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return vectors.count
    }

    public func upsert(id: String, vector: [Float]) {
        let v = Self.normalized(vector)
        lock.lock(); vectors[id] = v; lock.unlock()
    }

    public func remove(id: String) {
        lock.lock(); vectors[id] = nil; lock.unlock()
    }

    public func search(_ query: [Float], k: Int) -> [(id: String, score: Float)] {
        let q = Self.normalized(query)
        let n = vDSP_Length(q.count)

        lock.lock()
        let snapshot = vectors
        lock.unlock()

        var scored: [(id: String, score: Float)] = []
        scored.reserveCapacity(snapshot.count)
        for (id, vec) in snapshot where vec.count == q.count {
            var dot: Float = 0
            vDSP_dotpr(q, 1, vec, 1, &dot, n)
            scored.append((id, dot))
        }
        scored.sort { $0.score > $1.score }
        if scored.count > k { scored.removeLast(scored.count - k) }
        return scored
    }

    /// L2-normalize so cosine similarity reduces to a dot product.
    static func normalized(_ v: [Float]) -> [Float] {
        var norm: Float = 0
        vDSP_svesq(v, 1, &norm, vDSP_Length(v.count))
        norm = sqrt(norm)
        guard norm > 1e-12 else { return v }
        var out = [Float](repeating: 0, count: v.count)
        var inv = 1 / norm
        vDSP_vsmul(v, 1, &inv, &out, 1, vDSP_Length(v.count))
        return out
    }
}
