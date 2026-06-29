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

import Foundation
import os.log

/// BPE tokenizer loaded from a bundled `tokenizer.json` vocabulary file.
///
/// The vocabulary JSON format follows the HuggingFace tokenizers schema:
/// ```json
/// {
///   "model": {
///     "vocab": { "<token>": <id>, ... },
///     "merges": ["a b", "c d", ...]
///   },
///   "added_tokens": [ { "id": 0, "content": "<unk>", ... } ],
///   "bos_token": "<s>",
///   "eos_token": "</s>",
///   "unk_token": "<unk>"
/// }
/// ```
final class Tokenizer: @unchecked Sendable {

    // MARK: - Types

    enum TokenizerError: Error, LocalizedError {
        case vocabFileNotFound(String)
        case invalidVocabFormat
        case unknownToken(String)

        var errorDescription: String? {
            switch self {
            case .vocabFileNotFound(let name): return "Tokenizer vocab file '\(name)' not found in bundle."
            case .invalidVocabFormat:          return "Tokenizer vocab JSON has an unexpected format."
            case .unknownToken(let tok):       return "Token '\(tok)' not found in vocabulary."
            }
        }
    }

    // MARK: - Properties

    /// Map from token string → token ID.
    private let vocab: [String: Int]
    /// Reverse map: token ID → token string.
    private let reverseVocab: [Int: String]
    /// BPE merge rules in priority order (earlier index = higher priority).
    private let merges: [(String, String)]

    let bosTokenId: Int
    let eosTokenId: Int
    let unkTokenId: Int
    let padTokenId: Int

    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "Tokenizer")

    // MARK: - Init

    /// Load from a `tokenizer.json` inside `bundle` (defaults to `.main`).
    init(vocabFilename: String = "tokenizer", bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: vocabFilename, withExtension: "json") else {
            throw TokenizerError.vocabFileNotFound(vocabFilename)
        }
        let data = try Data(contentsOf: url)
        let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let raw else { throw TokenizerError.invalidVocabFormat }

        // Parse vocab
        let model = raw["model"] as? [String: Any]
        guard let vocabRaw = model?["vocab"] as? [String: Int] else {
            throw TokenizerError.invalidVocabFormat
        }
        vocab = vocabRaw
        reverseVocab = Dictionary(uniqueKeysWithValues: vocabRaw.map { ($1, $0) })

        // Parse BPE merges
        let mergesRaw = (model?["merges"] as? [String]) ?? []
        merges = mergesRaw.compactMap { line -> (String, String)? in
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return (parts[0], parts[1])
        }

        // Special tokens
        let addedTokens = (raw["added_tokens"] as? [[String: Any]]) ?? []
        func specialId(for key: String) -> Int {
            let content = raw[key] as? String ?? ""
            return vocabRaw[content]
                ?? addedTokens.first(where: { $0["content"] as? String == content })
                    .flatMap { $0["id"] as? Int }
                ?? 0
        }

        bosTokenId = specialId(for: "bos_token")
        eosTokenId = specialId(for: "eos_token")
        unkTokenId = specialId(for: "unk_token")
        padTokenId = specialId(for: "pad_token")

        logger.info("Tokenizer loaded. Vocab size: \(self.vocab.count)")
    }

    // MARK: - Public API

    /// Encode a string into a sequence of token IDs.
    /// Prepends the BOS token automatically.
    func encode(_ text: String) -> [Int] {
        var tokens: [Int] = [bosTokenId]
        let words = pretokenize(text)
        for word in words {
            let wordTokens = bpeEncode(word)
            tokens.append(contentsOf: wordTokens)
        }
        return tokens
    }

    /// Decode a sequence of token IDs back to a string.
    func decode(_ ids: [Int]) -> String {
        ids
            .filter { $0 != bosTokenId && $0 != eosTokenId && $0 != padTokenId }
            .compactMap { reverseVocab[$0] }
            .joined()
            .replacingOccurrences(of: "▁", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Decode a single token ID (used during streaming).
    func decodeSingle(_ id: Int) -> String {
        (reverseVocab[id] ?? "")
            .replacingOccurrences(of: "▁", with: " ")
    }

    /// Total number of entries in the vocabulary.
    var vocabSize: Int { vocab.count }

    // MARK: - BPE

    /// Simple whitespace + punctuation pre-tokenizer.
    /// Prefixes each word with "▁" (SentencePiece convention) to mark word boundaries.
    private func pretokenize(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        for char in text {
            if char.isWhitespace {
                if !current.isEmpty {
                    words.append("▁" + current)
                    current = ""
                }
            } else if char.isPunctuation || char.isSymbol {
                if !current.isEmpty {
                    words.append("▁" + current)
                    current = ""
                }
                words.append(String(char))
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            words.append("▁" + current)
        }
        return words
    }

    /// BPE encode a single word segment into token IDs.
    private func bpeEncode(_ word: String) -> [Int] {
        // Start with individual characters
        var symbols: [String] = word.map(String.init)

        // Build a priority map: merge pair → merge rank
        var mergeRank: [(String, String): Int] = [:]
        for (rank, pair) in merges.enumerated() {
            mergeRank[pair] = rank
        }

        // Iteratively apply lowest-rank (highest priority) merges
        while symbols.count > 1 {
            var bestRank = Int.max
            var bestIdx = -1

            for i in 0..<(symbols.count - 1) {
                let pair = (symbols[i], symbols[i + 1])
                if let rank = mergeRank[pair], rank < bestRank {
                    bestRank = rank
                    bestIdx = i
                }
            }

            guard bestIdx >= 0 else { break }

            let merged = symbols[bestIdx] + symbols[bestIdx + 1]
            symbols.remove(at: bestIdx + 1)
            symbols[bestIdx] = merged
        }

        return symbols.map { vocab[$0] ?? unkTokenId }
    }
}
