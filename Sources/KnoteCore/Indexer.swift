import Foundation
import KnoteEmbeddings
import KnoteVector

/// Keeps the vector index and stored embeddings in sync with the note store
/// (ARCHITECTURE.md §5). All embedding work happens off the main thread.
public final class Indexer: @unchecked Sendable {
    private let store: NoteStore
    private let encoder: Encoder
    private let index: VectorIndex
    private let queue = DispatchQueue(label: "com.knote.indexer", qos: .utility)

    public init(store: NoteStore, encoder: Encoder, index: VectorIndex) {
        self.store = store
        self.encoder = encoder
        self.index = index
    }

    /// Load existing vectors into the index and backfill any missing ones.
    public func warmUp() {
        queue.async { [self] in
            if let pairs = try? store.loadEmbeddings(model: encoder.id) {
                for p in pairs { index.upsert(id: p.id, vector: p.vector) }
            }
            if let missing = try? store.idsMissingEmbedding(model: encoder.id) {
                for id in missing { embed(id: id) }
            }
        }
    }

    /// (Re)embed a note after create/update.
    public func indexNote(_ note: Note) {
        queue.async { [self] in embed(id: note.id, body: note.body) }
    }

    public func removeNote(id: String) {
        index.remove(id: id)
    }

    private func embed(id: String, body: String? = nil) {
        let text: String
        if let body { text = body }
        else if let n = try? store.fetch(id: id) { text = n.body }
        else { return }
        guard let vec = encoder.embed(text, kind: .document) else { return }
        try? store.saveEmbedding(noteID: id, model: encoder.id, vector: vec)
        index.upsert(id: id, vector: vec)
    }
}
