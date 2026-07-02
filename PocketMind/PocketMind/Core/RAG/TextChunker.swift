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

/// Splits a document into overlapping sentence-boundary chunks suitable for embedding.
///
/// Each chunk is sized to fit ~50 tokens so that the retrieved context block, the user
/// message, and the model's response all fit within the 256-token context window.
enum TextChunker {

    static let chunkCharLimit = 220
    static let overlapSentences = 1

    /// Returns non-empty chunks from `text`, each at most `chunkCharLimit` characters.
    static func chunk(_ text: String) -> [String] {
        let sentences = sentences(from: text)
        guard !sentences.isEmpty else { return [] }

        var chunks: [String] = []
        var buffer: [String] = []
        var bufferLength = 0

        for sentence in sentences {
            let sentenceLen = sentence.count
            if bufferLength + sentenceLen > chunkCharLimit, !buffer.isEmpty {
                let chunk = buffer.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                if !chunk.isEmpty { chunks.append(chunk) }

                // Keep the last sentence as overlap so the next chunk has bridging context.
                buffer = Array(buffer.suffix(overlapSentences))
                bufferLength = buffer.map(\.count).reduce(0, +)
            }
            buffer.append(sentence)
            bufferLength += sentenceLen
        }

        if let last = buffer.joined(separator: " ").trimmingCharacters(in: .whitespaces) as String?,
           !last.isEmpty {
            chunks.append(last)
        }
        return chunks
    }

    private static func sentences(from text: String) -> [String] {
        let normalised = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalised.isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = normalised

        var results: [String] = []
        tokenizer.enumerateTokens(in: normalised.startIndex..<normalised.endIndex) { range, _ in
            let s = normalised[range]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !s.isEmpty { results.append(s) }
            return true
        }
        return results
    }
}
