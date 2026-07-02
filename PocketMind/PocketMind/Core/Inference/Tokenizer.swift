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
/// Implements byte-level BPE (GPT-2 / Llama 3 / tiktoken style) with the
/// full Llama 3 pre-tokenization regex. Decoding reverses the unicode-to-byte
/// mapping so `Ġ` → space, `Ċ` → newline, etc.
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

    private let vocab: [String: Int]
    private let addedTokenVocab: [String: Int]    // IDs from added_tokens (may not be in model.vocab)
    private let reverseAddedTokenVocab: [Int: String] // reverse of addedTokenVocab for O(1) stop-token checks
    private let reverseVocab: [Int: String]
    private let merges: [(String, String)]
    private let mergeRank: [String: Int]      // pre-built for O(1) per-step lookup
    private let specialTokenStrings: [String] // sorted longest-first for greedy match

    let bosTokenId: Int
    let eosTokenId: Int
    let unkTokenId: Int
    let padTokenId: Int

    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "Tokenizer")

    // MARK: - Byte-level BPE maps (GPT-2 / Llama 3 byte_to_unicode)

    private static let bpeMaps: (toUnicode: [UInt8: Character], toBytes: [Character: UInt8]) = {
        // Bytes that map to themselves (printable ASCII + extended Latin)
        var bs = Array(33...126) + Array(161...172) + Array(174...255)
        var cs = bs
        var n = 0
        // Remaining bytes (control chars + non-printable) get assigned starting at U+0100
        for b in 0..<256 where !bs.contains(b) {
            bs.append(b)
            cs.append(256 + n)
            n += 1
        }
        var fwd: [UInt8: Character] = [:]
        var rev: [Character: UInt8] = [:]
        for i in 0..<bs.count {
            guard let scalar = Unicode.Scalar(cs[i]) else { continue }
            let ch = Character(scalar)
            fwd[UInt8(bs[i])] = ch
            rev[ch] = UInt8(bs[i])
        }
        return (fwd, rev)
    }()

    private static var bytesToUnicode: [UInt8: Character] { bpeMaps.toUnicode }
    private static var unicodeToBytes: [Character: UInt8] { bpeMaps.toBytes }

    // MARK: - Pre-tokenization regex (Llama 3 / GPT-4 tiktoken pattern)

    // swiftlint:disable:next force_try
    private static let pretokRegex: NSRegularExpression = try! NSRegularExpression(
        pattern: #"(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\r\n\p{L}\p{N}]?\p{L}+|\p{N}{1,3}| ?[^\s\p{L}\p{N}]+[\r\n]*|\s*[\r\n]+|\s+(?!\S)|\s+"#,
        options: []
    )

    // MARK: - Init (placeholder)

    /// Internal init used when the tokenizer.json isn't bundled yet.
    init(
        vocab: [String: Int], reverseVocab: [Int: String], merges: [(String, String)],
        bosTokenId: Int, eosTokenId: Int, unkTokenId: Int, padTokenId: Int
    ) {
        self.vocab = vocab
        self.addedTokenVocab = [:]
        self.reverseAddedTokenVocab = [:]
        self.reverseVocab = reverseVocab
        self.merges = merges
        self.mergeRank = Dictionary(uniqueKeysWithValues:
            merges.enumerated().map { ($1.0 + "\0" + $1.1, $0) }
        )
        self.specialTokenStrings = vocab.keys
            .filter { $0.hasPrefix("<|") && $0.hasSuffix("|>") }
            .sorted { $0.count > $1.count }
        self.bosTokenId = bosTokenId
        self.eosTokenId = eosTokenId
        self.unkTokenId = unkTokenId
        self.padTokenId = padTokenId
    }

    // MARK: - Init (from bundle)

    /// Load from a `tokenizer.json` inside `bundle` (defaults to `.main`).
    init(vocabFilename: String = "tokenizer", bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: vocabFilename, withExtension: "json") else {
            throw TokenizerError.vocabFileNotFound(vocabFilename)
        }
        let data = try Data(contentsOf: url)
        let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let raw else { throw TokenizerError.invalidVocabFormat }

        let model = raw["model"] as? [String: Any]
        guard let vocabRaw = model?["vocab"] as? [String: Int] else {
            throw TokenizerError.invalidVocabFormat
        }
        vocab = vocabRaw
        reverseVocab = Dictionary(uniqueKeysWithValues: vocabRaw.map { ($1, $0) })

        let mergesRaw = (model?["merges"] as? [String]) ?? []
        let parsedMerges: [(String, String)] = mergesRaw.compactMap { line -> (String, String)? in
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return (parts[0], parts[1])
        }
        merges = parsedMerges
        mergeRank = Dictionary(uniqueKeysWithValues:
            parsedMerges.enumerated().map { ($1.0 + "\0" + $1.1, $0) }
        )

        // Parse special tokens — handle both string and dict form in tokenizer.json
        let addedTokens = (raw["added_tokens"] as? [[String: Any]]) ?? []
        func specialId(for key: String) -> Int {
            let field = raw[key]
            let content: String
            if let str = field as? String {
                content = str
            } else if let dict = field as? [String: Any], let c = dict["content"] as? String {
                content = c
            } else {
                content = ""
            }
            return vocabRaw[content]
                ?? addedTokens.first(where: { $0["content"] as? String == content })
                    .flatMap { $0["id"] as? Int }
                ?? 0
        }

        bosTokenId = specialId(for: "bos_token")
        eosTokenId = specialId(for: "eos_token")
        unkTokenId = specialId(for: "unk_token")
        padTokenId = specialId(for: "pad_token")

        // Build added_tokens vocab: special tokens may appear ONLY in added_tokens and not
        // in model.vocab. The encoder checks this dict as fallback so they aren't silently dropped.
        let addedPairs: [(String, Int)] = addedTokens.compactMap { d -> (String, Int)? in
            guard let content = d["content"] as? String,
                  let id = d["id"] as? Int else { return nil }
            return (content, id)
        }
        addedTokenVocab = Dictionary(uniqueKeysWithValues: addedPairs)
        // Reverse map used by isStopToken: <|eot_id|> (id 128009) lives here, not in reverseVocab.
        reverseAddedTokenVocab = Dictionary(uniqueKeysWithValues: addedPairs.map { ($1, $0) })

        // Build special-token string list for encoder's greedy scan
        let addedContents = addedTokens.compactMap { $0["content"] as? String }
        let vocabSpecials = vocabRaw.keys.filter { $0.hasPrefix("<") }
        specialTokenStrings = Array(Set(vocabSpecials + addedContents))
            .sorted { $0.count > $1.count }

        logger.info("Tokenizer loaded. Vocab size: \(self.vocab.count)")
    }

    // MARK: - Public API

    /// Encode text into token IDs. Handles special tokens (e.g. `<|begin_of_text|>`)
    /// with a greedy longest-match scan before applying byte-level BPE.
    func encode(_ text: String) -> [Int] {
        var result: [Int] = []
        var remaining = text[...]

        while !remaining.isEmpty {
            // Greedy special-token scan (longest-first); check both model.vocab and added_tokens
            var foundSpecial = false
            for special in specialTokenStrings {
                if remaining.hasPrefix(special),
                   let id = vocab[special] ?? addedTokenVocab[special] {
                    result.append(id)
                    remaining = remaining.dropFirst(special.count)
                    foundSpecial = true
                    break
                }
            }
            if foundSpecial { continue }

            // Collect up to the next special token boundary
            var chunkEnd = remaining.startIndex
            while chunkEnd < remaining.endIndex {
                let tail = remaining[chunkEnd...]
                if specialTokenStrings.contains(where: { tail.hasPrefix($0) }) { break }
                remaining.formIndex(after: &chunkEnd)
            }
            let chunk = String(remaining[..<chunkEnd])
            remaining = remaining[chunkEnd...]
            result.append(contentsOf: bpeTokenize(chunk))
        }
        return result
    }

    /// Decode token IDs back to a plain string.
    func decode(_ ids: [Int]) -> String {
        let bytes = ids
            .filter { $0 != bosTokenId && $0 != eosTokenId && $0 != padTokenId }
            .compactMap { reverseVocab[$0] }
            .filter { !isSpecialToken($0) }
            .flatMap { tokenToBytes($0) }
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }

    /// Decode a single token ID for streaming output.
    func decodeSingle(_ id: Int) -> String {
        guard let tokenStr = reverseVocab[id] else { return "" }
        if isSpecialToken(tokenStr) { return "" }
        let bytes = tokenToBytes(tokenStr)
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }

    /// Returns true when `id` should stop generation (EOS or Llama 3 end-of-turn).
    func isStopToken(_ id: Int) -> Bool {
        if id == eosTokenId { return true }
        // <|eot_id|> (128009) lives in addedTokenVocab, not in reverseVocab which is
        // built only from model.vocab — check both so generation stops at end-of-turn.
        let str = reverseVocab[id] ?? reverseAddedTokenVocab[id]
        guard let str else { return false }
        return str == "<|eot_id|>" || str == "<|end_of_text|>"
    }

    var vocabSize: Int { vocab.count }

    // MARK: - BPE pipeline

    private func bpeTokenize(_ text: String) -> [Int] {
        pretokenize(text).flatMap { bpeEncode($0) }
    }

    private func pretokenize(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        return Self.pretokRegex.matches(in: text, range: range).map { ns.substring(with: $0.range) }
    }

    private func bpeEncode(_ piece: String) -> [Int] {
        // Convert each UTF-8 byte to its byte-level BPE unicode character
        let unicodeStr = piece.utf8.compactMap { Self.bytesToUnicode[$0] }.map(String.init).joined()
        guard !unicodeStr.isEmpty else { return [] }

        // Fast path: direct vocab lookup for the whole piece
        if let id = vocab[unicodeStr] { return [id] }

        // Start with individual unicode characters as symbols
        var symbols = unicodeStr.map(String.init)

        // Iteratively merge the highest-priority (lowest-rank) adjacent pair
        while symbols.count > 1 {
            var bestRank = Int.max
            var bestIdx  = -1
            for i in 0..<(symbols.count - 1) {
                if let rank = mergeRank[symbols[i] + "\0" + symbols[i + 1]], rank < bestRank {
                    bestRank = rank
                    bestIdx  = i
                }
            }
            guard bestIdx >= 0 else { break }
            symbols[bestIdx] = symbols[bestIdx] + symbols[bestIdx + 1]
            symbols.remove(at: bestIdx + 1)
        }

        return symbols.map { vocab[$0] ?? unkTokenId }
    }

    // MARK: - Byte-level decode

    private func tokenToBytes(_ tokenStr: String) -> [UInt8] {
        tokenStr.compactMap { Self.unicodeToBytes[$0] }
    }

    private func isSpecialToken(_ str: String) -> Bool {
        (str.hasPrefix("<|") && str.hasSuffix("|>")) ||
        (str.hasPrefix("<") && str.hasSuffix(">") && str.count > 2 && !str.contains(" "))
    }
}
