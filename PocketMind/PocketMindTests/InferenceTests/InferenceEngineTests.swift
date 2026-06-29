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

import CoreML
import XCTest
@testable import PocketMind

/// Tests for `InferenceEngine` — these use a real (tiny) CoreML model
/// or verify the engine's state-machine behaviour without an actual model.
final class InferenceEngineTests: XCTestCase {

    // MARK: - isLoaded

    func testIsLoadedReturnsFalseBeforeLoad() async throws {
        let engine = makeEngine()
        let loaded = await engine.isLoaded()
        XCTAssertFalse(loaded, "Engine must report not loaded before loadModel() is called.")
    }

    func testUnloadModelSetsLoadedToFalse() async throws {
        let engine = makeEngine()
        // Even without a real model, unload should be a no-op that doesn't crash
        await engine.unloadModel()
        let loaded = await engine.isLoaded()
        XCTAssertFalse(loaded)
    }

    // MARK: - loadModel with non-existent URL

    func testLoadModelThrowsWhenFileAbsent() async {
        let missingURL = URL(fileURLWithPath: "/nonexistent/model.mlpackage")
        let tok = makeTinyTokenizer()
        let engine = InferenceEngine(modelURL: missingURL, tokenizer: tok)

        do {
            try await engine.loadModel()
            XCTFail("Expected modelNotFound error.")
        } catch InferenceEngine.InferenceError.modelNotFound {
            // Expected
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - generate() with no model

    func testGenerateFinishesCleanlyWhenModelMissing() async {
        let engine = makeEngine()
        var receivedFinished = false
        var tokenCount = 0

        let stream = await engine.generate(prompt: "Hello", maxTokens: 5)
        for await token in stream {
            if token.isFinished {
                receivedFinished = true
            } else {
                tokenCount += 1
            }
        }

        XCTAssertTrue(receivedFinished, "Stream must always emit a finished token.")
        // No tokens expected since model is missing
        XCTAssertEqual(tokenCount, 0)
    }

    // MARK: - maxTokens respected (with mock model)

    func testGenerateRespectsMaxTokensLimit() async throws {
        guard let engine = makeEngineWithTinyCoreMLModel() else {
            throw XCTSkip("No tiny test CoreML model available — skipping full generate test.")
        }

        let maxTokens = 3
        var nonFinishedCount = 0
        var receivedFinished = false

        let stream = await engine.generate(prompt: "hi", maxTokens: maxTokens)
        for await token in stream {
            if token.isFinished {
                receivedFinished = true
            } else {
                nonFinishedCount += 1
            }
        }

        XCTAssertTrue(receivedFinished)
        XCTAssertLessThanOrEqual(nonFinishedCount, maxTokens,
            "Generated tokens must not exceed maxTokens.")
    }

    // MARK: - Stream always terminates

    func testGenerateStreamAlwaysTerminates() async {
        let engine = makeEngine()
        // Stream must complete even with no model — no hang
        let expectation = expectation(description: "Stream terminates")
        Task {
            let stream = await engine.generate(prompt: "test", maxTokens: 10)
            for await _ in stream { }
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 5.0)
    }

    // MARK: - Helpers

    private func makeEngine() -> InferenceEngine {
        let fakeURL = URL(fileURLWithPath: "/fake/model.mlpackage")
        let tok = makeTinyTokenizer()
        return InferenceEngine(modelURL: fakeURL, tokenizer: tok, contextLength: 128)
    }

    private func makeTinyTokenizer() -> Tokenizer {
        // Fall back to a stub tokenizer for unit testing
        (try? TokenizerStub()) ?? TokenizerStub.fallback()
    }

    /// Attempts to locate a pre-built tiny CoreML test model in the test bundle.
    private func makeEngineWithTinyCoreMLModel() -> InferenceEngine? {
        guard let url = Bundle(for: Self.self).url(
            forResource: "TestModel",
            withExtension: "mlpackage"
        ) else { return nil }
        return InferenceEngine(modelURL: url, tokenizer: makeTinyTokenizer(), contextLength: 128)
    }
}

// MARK: - TokenizerStub

/// Minimal tokenizer stub for tests that don't need a real vocab file.
private final class TokenizerStub: Tokenizer {

    static func fallback() -> TokenizerStub {
        // This can't actually fail with the minimal JSON below
        return try! TokenizerStub()  // swiftlint:disable:this force_try
    }

    override init(vocabFilename: String = "tokenizer", bundle: Bundle = .main) throws {
        // Write a temp minimal vocab and init from that
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TokenizerStub")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let json: [String: Any] = [
            "model": [
                "vocab": ["<unk>": 0, "<s>": 1, "</s>": 2, "▁hi": 3, "▁test": 4] as [String: Int],
                "merges": [] as [String],
            ],
            "added_tokens": [["id": 0, "content": "<unk>"], ["id": 1, "content": "<s>"], ["id": 2, "content": "</s>"]],
            "bos_token": "<s>",
            "eos_token": "</s>",
            "unk_token": "<unk>",
            "pad_token": "<unk>",
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let url = tempDir.appendingPathComponent("tokenizer.json")
        try data.write(to: url)

        class TempBundle: Bundle {
            let tempDir: URL
            init(tempDir: URL) { self.tempDir = tempDir; super.init() }
            override func url(forResource name: String?, withExtension ext: String?) -> URL? {
                guard let name, let ext else { return nil }
                let c = tempDir.appendingPathComponent("\(name).\(ext)")
                return FileManager.default.fileExists(atPath: c.path) ? c : nil
            }
        }
        try super.init(vocabFilename: "tokenizer", bundle: TempBundle(tempDir: tempDir))
    }
}
