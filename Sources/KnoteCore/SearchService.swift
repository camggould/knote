import Foundation
import KnoteEmbeddings
import KnoteVector

public struct SearchResult: Identifiable, Equatable, Sendable {
    public var note: Note
    public var score: Double
    public var tags: [String]
    public var id: String { note.id }

    public init(note: Note, score: Double, tags: [String] = []) {
        self.note = note
        self.score = score
        self.tags = tags
    }
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

        // Extract #tags from query
        let (queryTags, freeTextQuery) = extractTagsFromQuery(trimmed)

        // If tags present: compute intersection of candidate note IDs
        var candidateNoteIDs: Set<String>?
        if !queryTags.isEmpty {
            var intersection: Set<String>? = nil
            for tag in queryTags {
                let tagNoteIDs = Set((try? store.noteIDs(withTag: tag)) ?? [])
                if let current = intersection {
                    intersection = current.intersection(tagNoteIDs)
                } else {
                    intersection = tagNoteIDs
                }
            }
            candidateNoteIDs = intersection
        }

        // If no free text and we have tag candidates, return them sorted by recency
        if freeTextQuery.isEmpty {
            if let candidates = candidateNoteIDs {
                let notes = (try? store.fetch(ids: Array(candidates))) ?? [:]
                let results = candidates
                    .compactMap { id -> SearchResult? in
                        guard let note = notes[id] else { return nil }
                        let tagNames = (try? store.tags(noteID: id))?.map(\.name) ?? []
                        return SearchResult(note: note, score: 0, tags: tagNames)
                    }
                    .sorted { $0.note.updatedAt > $1.note.updatedAt }
                return Array(results.prefix(config.limit))
            }
            return []
        }

        // Run semantic + lexical ranking on free text
        var rrf: [String: Double] = [:]
        if let qv = encoder.embed(freeTextQuery, kind: .query) {
            let sem = index.search(qv, k: config.semanticK)
            addRRF(&rrf, ranked: sem.map { $0.id })
        }

        if let lex = try? store.lexicalSearch(freeTextQuery, limit: config.lexicalK) {
            addRRF(&rrf, ranked: lex.map { $0.id })
        }

        // Filter to candidates if tags were specified
        let candidateIDs: [String]
        if let candidates = candidateNoteIDs {
            candidateIDs = rrf.keys.filter { candidates.contains($0) }.sorted()
        } else {
            candidateIDs = Array(rrf.keys)
        }

        guard !candidateIDs.isEmpty else { return [] }

        // Fetch notes and populate tags
        let notes = (try? store.fetch(ids: candidateIDs)) ?? [:]
        let now = Date()
        let results = candidateIDs.compactMap { id -> SearchResult? in
            guard let note = notes[id] else { return nil }
            let tagNames = (try? store.tags(noteID: id))?.map(\.name) ?? []
            let score = (rrf[id] ?? 0) * recencyBoost(note.updatedAt, now: now)
            return SearchResult(note: note, score: score, tags: tagNames)
        }
        .sorted { $0.score > $1.score }
        return Array(results.prefix(config.limit))
    }

    /// Scoped search: restricts results to notes belonging to `spaceID`.
    /// When `spaceID` is nil, delegates to the global `search(_:)`.
    public func search(_ query: String, spaceID: String?) -> [SearchResult] {
        guard let spaceID else { return search(query) }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return recents(spaceID: spaceID) }
        return search(query).filter { $0.note.spaceId == spaceID }
    }

    /// Scoped recents: restricts results to notes belonging to `spaceID`.
    /// When `spaceID` is nil, delegates to the global `recents()`.
    public func recents(spaceID: String?) -> [SearchResult] {
        guard let spaceID else { return recents() }
        return recents().filter { $0.note.spaceId == spaceID }
    }

    /// Home state: most recently updated notes.
    public func recents() -> [SearchResult] {
        let notes = (try? store.recent(limit: config.limit)) ?? []
        return notes.map { note in
            let tagNames = (try? store.tags(noteID: note.id))?.map(\.name) ?? []
            return SearchResult(note: note, score: 0, tags: tagNames)
        }
    }

    /// Extract tags and free text from query.
    /// Returns (tags: [String], freeText: String)
    private func extractTagsFromQuery(_ query: String) -> (tags: [String], freeText: String) {
        var tags = Set<String>()
        var freeTextParts: [String] = []
        let pattern = try! NSRegularExpression(pattern: "#([A-Za-z0-9_]+)", options: [])
        let range = NSRange(query.startIndex..<query.endIndex, in: query)

        var lastEnd = query.startIndex
        let matches = pattern.matches(in: query, options: [], range: range)

        for match in matches {
            if let matchRange = Range(match.range, in: query) {
                // Add free text between last match and this one
                let freeTextPart = String(query[lastEnd..<matchRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                if !freeTextPart.isEmpty {
                    freeTextParts.append(freeTextPart)
                }
                // Extract tag name
                if let tagRange = Range(match.range(at: 1), in: query) {
                    let tagName = String(query[tagRange]).lowercased()
                    tags.insert(tagName)
                }
                lastEnd = matchRange.upperBound
            }
        }

        // Add remaining free text
        let remaining = String(query[lastEnd...]).trimmingCharacters(in: .whitespaces)
        if !remaining.isEmpty {
            freeTextParts.append(remaining)
        }

        let freeText = freeTextParts.joined(separator: " ")
        return (Array(tags).sorted(), freeText)
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
