import Foundation
import CoreML

/// The target encoder: `bge-small-en-v1.5` (384-dim) running on-device via Core
/// ML, with a self-contained WordPiece tokenizer (ARCHITECTURE.md §7).
///
/// Activates automatically once `scripts/convert_model.py` has produced the
/// model + `vocab.txt`. Until then the app uses `NLEmbeddingEncoder`.
public final class CoreMLEncoder: Encoder, @unchecked Sendable {
    public let id = "bge-small-en.v1"
    public let dimension: Int
    private let model: MLModel
    private let tokenizer: WordPieceTokenizer
    private let maxLength = 512
    private let queryInstruction = "Represent this sentence for searching relevant passages: "

    /// `modelURL` is a compiled `.mlmodelc` or an `.mlpackage` (compiled on the
    /// fly). Fails if either artifact is missing or unreadable.
    public init?(modelURL: URL, vocabURL: URL, dimension: Int = 384) {
        guard let tok = WordPieceTokenizer(vocabURL: vocabURL) else { return nil }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        let compiledURL: URL
        if modelURL.pathExtension == "mlmodelc" {
            compiledURL = modelURL
        } else if let c = try? MLModel.compileModel(at: modelURL) {
            compiledURL = c
        } else {
            return nil
        }
        guard let m = try? MLModel(contentsOf: compiledURL, configuration: config) else { return nil }
        self.model = m
        self.tokenizer = tok
        self.dimension = dimension
    }

    public func embed(_ text: String, kind: EmbedKind) -> [Float]? {
        let input = kind == .query ? queryInstruction + text : text
        let ids = tokenizer.encode(input, maxLength: maxLength)
        let len = ids.count

        guard let inputIds = try? MLMultiArray(shape: [1, NSNumber(value: len)], dataType: .int32),
              let mask = try? MLMultiArray(shape: [1, NSNumber(value: len)], dataType: .int32)
        else { return nil }
        for i in 0..<len {
            inputIds[i] = NSNumber(value: ids[i])
            mask[i] = 1
        }

        let provider = try? MLDictionaryFeatureProvider(dictionary: [
            "input_ids": inputIds,
            "attention_mask": mask,
        ])
        guard let provider,
              let out = try? model.prediction(from: provider),
              let name = out.featureNames.first(where: { out.featureValue(for: $0)?.multiArrayValue != nil }),
              let arr = out.featureValue(for: name)?.multiArrayValue
        else { return nil }

        var vec = [Float](repeating: 0, count: arr.count)
        for i in 0..<arr.count { vec[i] = arr[i].floatValue }
        return vec
    }
}
