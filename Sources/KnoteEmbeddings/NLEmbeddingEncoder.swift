import Foundation
import NaturalLanguage

/// On-device encoder using Apple's built-in sentence embedding. Zero setup,
/// ships with macOS. This is the live fallback so semantic search works
/// immediately; `CoreMLEncoder` (BGE) supersedes it when the model is present.
public final class NLEmbeddingEncoder: Encoder, @unchecked Sendable {
    public let id: String
    public let dimension: Int
    private let embedding: NLEmbedding

    /// Fails if the OS sentence-embedding asset is unavailable for the language.
    public init?(language: NLLanguage = .english) {
        guard let e = NLEmbedding.sentenceEmbedding(for: language) else { return nil }
        self.embedding = e
        self.dimension = e.dimension
        self.id = "nl.\(language.rawValue).v1"
    }

    public func embed(_ text: String, kind: EmbedKind) -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let v = embedding.vector(for: trimmed) {
            return v.map(Float.init)
        }

        // Sentence embedding is tuned for sentence-length input; for longer or
        // awkward text, mean-pool per-sentence vectors (ARCHITECTURE.md §7).
        var pooled = [Double](repeating: 0, count: dimension)
        var n = 0
        for sentence in Self.sentences(of: trimmed) {
            guard let v = embedding.vector(for: sentence), v.count == dimension else { continue }
            for i in 0..<dimension { pooled[i] += v[i] }
            n += 1
        }
        guard n > 0 else { return nil }
        return pooled.map { Float($0 / Double(n)) }
    }

    private static func sentences(of text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var result: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let s = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { result.append(s) }
            return true
        }
        return result.isEmpty ? [text] : result
    }
}
