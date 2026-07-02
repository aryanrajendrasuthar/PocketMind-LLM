//
// PocketMind — On-Device Private LLM for iPhone
// Copyright (c) 2026 Aryan Suthar. All Rights Reserved.
//
// PROPRIETARY AND CONFIDENTIAL
// Unauthorized copying, distribution, modification, or use of this file,
// via any medium, is strictly prohibited without the express written
// permission of the copyright owner.
//
// For licensing inquiries: aryanrajendrasuthar@gmail.com
//

import NaturalLanguage
import Foundation

/// Computes dense sentence embeddings using Apple's on-device word embedding model.
///
/// `NLEmbedding.wordEmbedding(for: .english)` ships inside iOS 17+ — no model download
/// required. Sentence-level vectors are produced by mean-pooling the word vectors for
/// all recognised words in the text, then L2-normalising the result.
final class EmbeddingService: @unchecked Sendable {

    private let model: NLEmbedding?

    /// Dimensionality of the embedding vectors (300 for Apple's English model).
    let dimension: Int

    init() {
        let m = NLEmbedding.wordEmbedding(for: .english)
        self.model = m
        self.dimension = m?.dimension ?? 300
    }

    /// Returns a normalised embedding vector for `text`, or `nil` if no words were recognised.
    func embed(_ text: String) -> [Float]? {
        guard let model else { return nil }
        let dim = dimension

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        var accumulator = [Double](repeating: 0, count: dim)
        var count = 0

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range]).lowercased()
            if let vec = model.vector(for: word), vec.count == dim {
                for i in 0..<dim { accumulator[i] += vec[i] }
                count += 1
            }
            return true
        }

        guard count > 0 else { return nil }

        // Mean-pool
        var mean = accumulator.map { Float($0 / Double(count)) }

        // L2-normalise so cosine similarity == dot product
        var normSq: Float = 0
        for v in mean { normSq += v * v }
        let norm = normSq.squareRoot()
        guard norm > 0 else { return nil }
        for i in 0..<mean.count { mean[i] /= norm }

        return mean
    }

    /// Dot-product cosine similarity for two L2-normalised vectors; result in [−1, 1].
    func similarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        for i in 0..<a.count { dot += a[i] * b[i] }
        return dot
    }
}
