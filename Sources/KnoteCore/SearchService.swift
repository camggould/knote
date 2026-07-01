import Foundation
import KnoteEmbeddings
import KnoteVector

public struct SearchResult: Identifiable, Equatable, Sendable {
    public var note: Note
    public var score: Double
    public var id: String { note.id }
}

/// Blends semantic + lexical candidates via Reciprocal Rank Fusion, then applies
/// a gentle recency prior (ARCHITECTURE.md §9).
public final class SearchService: @unchecked Sendable {
    private let store: NoteStore
    private let encoder: Encoder
    private let index: VectorIndex
    public var config: RankingConfig

    public init(store: NoteStore, encoder: Encoder, index: VectorIndex,
                config: RankingConfig = RankingConfig()) {
        self.store = store
        self.encoder = encoder
        self.index = index
        self.config = config
    }

    public func search(_ query: String) -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return recents() }

        // 1. Semantic candidates.
        var rrf: [String: Double] = [:]
        if let qv = encoder.embed(trimmed, kind: .query) {
            let sem = index.search(qv, k: config.semanticK)
            addRRF(&rrf, ranked: sem.map { $0.id })
        }

        // 2. Lexical candidates (BM25, lower = better → already ascending).
        if let lex = try? store.lexicalSearch(trimmed, limit: config.lexicalK) {
            addRRF(&rrf, ranked: lex.map { $0.id })
        }

        guard !rrf.isEmpty else { return [] }

        // 3. Fetch notes, apply recency prior, sort, truncate.
        let notes = (try? store.fetch(ids: Array(rrf.keys))) ?? [:]
        let now = Date()
        let results = rrf.compactMap { id, fused -> SearchResult? in
            guard let note = notes[id] else { return nil }
            let score = fused * recencyBoost(note.updatedAt, now: now)
            return SearchResult(note: note, score: score)
        }
        .sorted { $0.score > $1.score }
        return Array(results.prefix(config.limit))
    }

    /// Home state: most recently updated notes.
    public func recents() -> [SearchResult] {
        let notes = (try? store.recent(limit: config.limit)) ?? []
        return notes.map { SearchResult(note: $0, score: 0) }
    }

    private func addRRF(_ acc: inout [String: Double], ranked: [String]) {
        for (i, id) in ranked.enumerated() {
            acc[id, default: 0] += 1.0 / (config.rrfK + Double(i + 1))
        }
    }

    private func recencyBoost(_ date: Date, now: Date) -> Double {
        let ageDays = max(0, now.timeIntervalSince(date) / 86_400)
        return exp(-log(2.0) * ageDays / config.recencyHalfLifeDays) * 0.5 + 0.75
    }
}
