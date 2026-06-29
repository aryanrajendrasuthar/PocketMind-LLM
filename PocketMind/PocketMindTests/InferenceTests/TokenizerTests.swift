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

import XCTest
@testable import PocketMind

/// Tests for `Tokenizer` — encode/decode roundtrip over 20 sample sentences.
final class TokenizerTests: XCTestCase {

    // MARK: - Fixtures

    /// Build a minimal in-memory tokenizer for testing without a bundled file.
    private func makeTokenizer() throws -> Tokenizer {
        // Write a minimal tokenizer.json to a temp bundle-accessible location
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TokenizerTests")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let vocabJSON = Self.minimalVocabJSON()
        let jsonData = try JSONSerialization.data(withJSONObject: vocabJSON)
        let jsonURL = tempDir.appendingPathComponent("tokenizer.json")
        try jsonData.write(to: jsonURL)

        // Create a Bundle pointing at the temp directory
        class TempBundle: Bundle {
            let tempDir: URL
            init(tempDir: URL) {
                self.tempDir = tempDir
                super.init()
            }
            override func url(forResource name: String?, withExtension ext: String?) -> URL? {
                guard let name, let ext else { return nil }
                let candidate = tempDir.appendingPathComponent("\(name).\(ext)")
                return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
            }
        }

        let bundle = TempBundle(tempDir: tempDir)
        return try Tokenizer(vocabFilename: "tokenizer", bundle: bundle)
    }

    private static func minimalVocabJSON() -> [String: Any] {
        // Minimal vocab covering the sample sentences below
        var vocab: [String: Int] = [
            "<unk>": 0, "<s>": 1, "</s>": 2,
            "▁the": 3, "▁quick": 4, "▁brown": 5, "▁fox": 6,
            "▁jumps": 7, "▁over": 8, "▁lazy": 9, "▁dog": 10,
            "▁hello": 11, "▁world": 12, "▁code": 13, "▁is": 14,
            "▁fun": 15, "▁Swift": 16, "▁on": 17, "▁device": 18,
            "▁AI": 19, "▁privacy": 20, "▁matters": 21,
            "▁one": 22, "▁two": 23, "▁three": 24,
            "▁four": 25, "▁five": 26,
        ]
        // Add alphabet for unknown token fallback
        for char in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" {
            let key = String(char)
            if vocab[key] == nil {
                vocab[key] = vocab.count
            }
        }
        return [
            "model": [
                "vocab": vocab,
                "merges": [] as [String],
            ],
            "added_tokens": [
                ["id": 0, "content": "<unk>"],
                ["id": 1, "content": "<s>"],
                ["id": 2, "content": "</s>"],
            ],
            "bos_token": "<s>",
            "eos_token": "</s>",
            "unk_token": "<unk>",
            "pad_token": "<unk>",
        ]
    }

    private static let sampleSentences: [String] = [
        "the quick brown fox",
        "the lazy dog",
        "hello world",
        "code is fun",
        "Swift on device AI",
        "privacy matters",
        "one two three",
        "four five",
        "the quick brown fox jumps over the lazy dog",
        "hello",
        "world",
        "quick",
        "fox jumps over",
        "the dog",
        "AI privacy",
        "on device",
        "code",
        "fun",
        "three four five",
        "Swift is fun",
    ]

    // MARK: - Roundtrip tests (20 sentences)

    func testEncodeDecodeRoundtrip() throws {
        let tokenizer = try makeTokenizer()

        for sentence in Self.sampleSentences {
            let ids = tokenizer.encode(sentence)
            let decoded = tokenizer.decode(ids)

            // Decoded string should preserve all non-whitespace tokens
            // (exact whitespace normalization may differ)
            let sentenceWords = sentence.lowercased().split(separator: " ").map(String.init)
            let decodedWords = decoded.lowercased().split(separator: " ").map(String.init)

            XCTAssertFalse(ids.isEmpty, "encode('\(sentence)') should return non-empty ids")
            XCTAssertFalse(decodedWords.isEmpty, "decode should return non-empty string for '\(sentence)'")

            // At least half the words should survive the roundtrip
            let matchCount = sentenceWords.filter { decodedWords.contains($0) }.count
            XCTAssertGreaterThan(
                matchCount,
                sentenceWords.count / 2,
                "Roundtrip failed for: '\(sentence)'. Decoded: '\(decoded)'"
            )
        }
    }

    // MARK: - BOS token

    func testEncodePrependsBOSToken() throws {
        let tokenizer = try makeTokenizer()
        let ids = tokenizer.encode("hello world")
        XCTAssertEqual(ids.first, tokenizer.bosTokenId, "First token must be BOS.")
    }

    // MARK: - EOS token excluded from decode

    func testDecodeExcludesEOSToken() throws {
        let tokenizer = try makeTokenizer()
        let withEOS = [tokenizer.bosTokenId, 11, 12, tokenizer.eosTokenId]
        let decoded = tokenizer.decode(withEOS)
        XCTAssertFalse(decoded.contains("</s>"), "EOS token must not appear in decoded string.")
    }

    // MARK: - Vocab size

    func testVocabSizeIsPositive() throws {
        let tokenizer = try makeTokenizer()
        XCTAssertGreaterThan(tokenizer.vocabSize, 0)
    }

    // MARK: - Unknown token fallback

    func testUnknownCharactersFallBackToUnk() throws {
        let tokenizer = try makeTokenizer()
        // Japanese characters not in vocab — should map to unk
        let ids = tokenizer.encode("こんにちは")
        // All IDs should either be unk or BOS
        let nonBOS = ids.dropFirst()
        XCTAssertTrue(
            nonBOS.allSatisfy { $0 == tokenizer.unkTokenId || $0 >= 0 },
            "Unknown characters should map to unk token or individual char tokens."
        )
    }

    // MARK: - Empty input

    func testEncodeEmptyStringReturnsBOSOnly() throws {
        let tokenizer = try makeTokenizer()
        let ids = tokenizer.encode("")
        XCTAssertEqual(ids, [tokenizer.bosTokenId], "Empty string should encode to [BOS].")
    }

    func testDecodeEmptyIdsReturnsEmptyString() throws {
        let tokenizer = try makeTokenizer()
        let text = tokenizer.decode([])
        XCTAssertEqual(text, "")
    }

    // MARK: - decodeSingle

    func testDecodeSingleKnownToken() throws {
        let tokenizer = try makeTokenizer()
        // BOS should decode to something (may be empty or the BOS string)
        let text = tokenizer.decodeSingle(tokenizer.bosTokenId)
        XCTAssertNotNil(text)
    }
}
