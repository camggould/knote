import Foundation

/// Minimal, dependency-free BERT WordPiece tokenizer (uncased) for the BGE
/// model. Self-contained so the app carries no heavy tokenizer dependency;
/// loads the standard `vocab.txt` produced alongside the converted model.
public struct WordPieceTokenizer {
    private let vocab: [String: Int]
    public let clsId: Int
    public let sepId: Int
    public let padId: Int
    public let unkId: Int
    private let maxInputChars = 200

    public init?(vocabURL: URL) {
        guard let text = try? String(contentsOf: vocabURL, encoding: .utf8) else { return nil }
        var v: [String: Int] = [:]
        for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let token = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty { v[token] = i }
        }
        guard let cls = v["[CLS]"], let sep = v["[SEP]"], let pad = v["[PAD]"], let unk = v["[UNK]"]
        else { return nil }
        vocab = v; clsId = cls; sepId = sep; padId = pad; unkId = unk
    }

    /// Token ids for `text`, wrapped in [CLS] … [SEP], truncated to `maxLength`.
    public func encode(_ text: String, maxLength: Int) -> [Int] {
        var ids = [clsId]
        for word in Self.basicSplit(text.lowercased()) {
            ids.append(contentsOf: wordpiece(word))
            if ids.count >= maxLength - 1 { break }
        }
        if ids.count > maxLength - 1 { ids = Array(ids.prefix(maxLength - 1)) }
        ids.append(sepId)
        return ids
    }

    private func wordpiece(_ word: String) -> [Int] {
        let chars = Array(word)
        if chars.count > maxInputChars { return [unkId] }
        var out: [Int] = []
        var start = 0
        while start < chars.count {
            var end = chars.count
            var match: Int? = nil
            while start < end {
                var sub = String(chars[start..<end])
                if start > 0 { sub = "##" + sub }
                if let id = vocab[sub] { match = id; break }
                end -= 1
            }
            guard let id = match else { return [unkId] }
            out.append(id)
            start = end
        }
        return out
    }

    /// Whitespace + punctuation splitting (BERT "basic" tokenization).
    private static func basicSplit(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for scalar in text.unicodeScalars {
            let c = Character(scalar)
            if c.isWhitespace {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else if isPunctuation(scalar) {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(c))
            } else {
                current.append(c)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func isPunctuation(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        if (v >= 33 && v <= 47) || (v >= 58 && v <= 64) || (v >= 91 && v <= 96) || (v >= 123 && v <= 126) {
            return true
        }
        return CharacterSet.punctuationCharacters.contains(s) || CharacterSet.symbols.contains(s)
    }
}
