import Foundation
import KnoteCore
import KnoteEmbeddings
import KnoteVector

/// Wires the domain services and picks the best available encoder:
/// Core ML BGE if the converted model is present, else Apple's NLEmbedding,
/// else a lexical-only fallback (FTS still works).
struct Services {
    let store: NoteStore
    let search: SearchService
    let indexer: Indexer
    let encoderName: String

    static func bootstrap() throws -> Services {
        let dir = try supportDirectory()
        let store = try NoteStore(path: dir.appendingPathComponent("knote.sqlite"))

        let (encoder, name) = makeEncoder(supportDir: dir)
        let index = InMemoryVectorIndex()
        let indexer = Indexer(store: store, encoder: encoder, index: index)
        let search = SearchService(store: store, encoder: encoder, index: index)

        return Services(store: store, search: search, indexer: indexer, encoderName: name)
    }

    /// Chooses the encoder *type* up front (a cheap file check) but defers
    /// constructing the underlying model until the first embed, so an idle
    /// menu-bar app stays light (ARCHITECTURE.md §7). The `id`/`dimension` are
    /// known ahead of load, which is all the index warm-up needs.
    private static func makeEncoder(supportDir: URL) -> (Encoder, String) {
        let modelDir = supportDir.appendingPathComponent("model")
        let vocab = modelDir.appendingPathComponent("vocab.txt")
        for ext in ["mlmodelc", "mlpackage"] {
            let model = modelDir.appendingPathComponent("bge-small-en.\(ext)")
            if FileManager.default.fileExists(atPath: model.path),
               FileManager.default.fileExists(atPath: vocab.path) {
                let lazy = LazyEncoder(id: "bge-small-en.v1", dimension: 384) {
                    CoreMLEncoder(modelURL: model, vocabURL: vocab)
                }
                return (lazy, "BGE small (Core ML)")
            }
        }
        // Default: Apple's on-device sentence embedding, loaded on first use.
        let lazy = LazyEncoder(id: "nl.en.v1", dimension: 512) {
            NLEmbeddingEncoder() ?? LexicalOnlyEncoder()
        }
        return (lazy, "Apple NLEmbedding")
    }

    private static func supportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("knote", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

/// Defers constructing the real encoder (and loading its model) until the first
/// `embed`, keeping idle memory low. `id`/`dimension` are fixed up front so the
/// vector-index warm-up can load the right stored embeddings without a model.
final class LazyEncoder: Encoder, @unchecked Sendable {
    let id: String
    let dimension: Int
    private let make: () -> Encoder?
    private var resolved: Encoder?
    private var didResolve = false
    private let lock = NSLock()

    init(id: String, dimension: Int, make: @escaping () -> Encoder?) {
        self.id = id
        self.dimension = dimension
        self.make = make
    }

    func embed(_ text: String, kind: EmbedKind) -> [Float]? {
        lock.lock()
        if !didResolve { resolved = make(); didResolve = true }
        let encoder = resolved
        lock.unlock()
        return encoder?.embed(text, kind: kind)
    }
}

/// Fallback encoder that produces no vectors; search degrades to lexical (FTS).
final class LexicalOnlyEncoder: Encoder, @unchecked Sendable {
    let id = "none.v1"
    let dimension = 0
    func embed(_ text: String, kind: EmbedKind) -> [Float]? { nil }
}
