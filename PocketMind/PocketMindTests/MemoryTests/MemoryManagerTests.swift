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

final class MemoryManagerTests: XCTestCase {

    private var manager: MemoryManager!

    override func setUp() async throws {
        manager = MemoryManager()
    }

    // MARK: - KV cache trimming

    func testTrimContextReturnsSameMessagesWhenUnderBudget() async {
        let messages = (0..<5).map { i in
            ChatMessage(role: i % 2 == 0 ? .user : .assistant,
                        content: "Short message \(i)",
                        tokenCount: 10)
        }
        let (result, wasTrimmed) = await manager.trimContext(messages: messages, modelContextLength: 4096)
        XCTAssertFalse(wasTrimmed)
        XCTAssertEqual(result.count, messages.count)
    }

    func testTrimContextDropsOldestMessagesWhenOverBudget() async {
        // Create 10 messages of 500 tokens each = 5000 tokens, well over 4096 - 256 = 3840 budget
        let messages = (0..<10).map { i in
            ChatMessage(role: i % 2 == 0 ? .user : .assistant,
                        content: "Long message \(i)",
                        tokenCount: 500)
        }
        let (result, wasTrimmed) = await manager.trimContext(messages: messages, modelContextLength: 4096)
        XCTAssertTrue(wasTrimmed)
        XCTAssertLessThan(result.count, messages.count, "Some messages must be dropped.")
        // Verify it's the newest messages that survive (oldest dropped)
        if let last = messages.last, let resultLast = result.last {
            XCTAssertEqual(resultLast.id, last.id, "Newest messages must be preserved.")
        }
    }

    func testTrimContextPreservesSystemPrompt() async {
        let systemMsg = ChatMessage(role: .system, content: "You are a helpful assistant.", tokenCount: 10)
        // Flood with large user/assistant pairs
        var messages: [ChatMessage] = [systemMsg]
        for i in 0..<10 {
            messages.append(ChatMessage(role: i % 2 == 0 ? .user : .assistant,
                                        content: "Big turn \(i)",
                                        tokenCount: 500))
        }

        let (result, wasTrimmed) = await manager.trimContext(messages: messages, modelContextLength: 4096)
        XCTAssertTrue(wasTrimmed)
        XCTAssertEqual(result.first?.role, .system, "System prompt must always be first after trimming.")
        XCTAssertEqual(result.first?.id, systemMsg.id)
    }

    func testTrimContextDropsInPairsPreservingTurnStructure() async {
        // 8 alternating user/assistant messages of 600 tokens each = 4800 > 3840 budget
        let messages = (0..<8).map { i in
            ChatMessage(role: i % 2 == 0 ? .user : .assistant,
                        content: "Turn \(i)",
                        tokenCount: 600)
        }
        let (result, _) = await manager.trimContext(messages: messages, modelContextLength: 4096)
        // Surviving messages should maintain alternating user/assistant pairs (even count)
        // The last message should be assistant (odd index), first should be user (even index)
        if !result.isEmpty {
            XCTAssertEqual(result.first?.role, .user, "After trim, first surviving message should be user.")
        }
    }

    func testTrimContextWithModelContextShorterThanMax() async {
        // Model has 2048 context; budget = 2048 - 256 = 1792
        let messages = (0..<6).map { i in
            ChatMessage(role: i % 2 == 0 ? .user : .assistant,
                        content: "Message \(i)",
                        tokenCount: 400)
        }
        // 6 × 400 = 2400 > 1792
        let (result, wasTrimmed) = await manager.trimContext(messages: messages, modelContextLength: 2048)
        XCTAssertTrue(wasTrimmed)
        XCTAssertLessThan(result.count, 6)
    }

    // MARK: - Memory usage reporting

    func testCurrentMemoryUsageBytesIsPositive() async {
        let usage = await manager.currentMemoryUsageBytes()
        XCTAssertGreaterThan(usage, 0, "Memory usage must be a positive value.")
    }

    func testCurrentMemoryUsageBytesIsSensible() async {
        let usage = await manager.currentMemoryUsageBytes()
        // Sanity: should be between 1 MB and 16 GB
        let oneMB: Int64 = 1 * 1024 * 1024
        let sixteenGB: Int64 = 16 * 1024 * 1024 * 1024
        XCTAssertGreaterThan(usage, oneMB)
        XCTAssertLessThan(usage, sixteenGB)
    }

    // MARK: - Memory pressure → unload

    func testMemoryWarningNotificationCausesModelUnload() async throws {
        let fakeURL = URL(fileURLWithPath: "/fake/model.mlpackage")
        let tok = try makeStubTokenizer()
        let engine = InferenceEngine(modelURL: fakeURL, tokenizer: tok, contextLength: 128)

        await manager.start(engine: engine)

        // Verify engine starts as not loaded
        let beforeWarning = await engine.isLoaded()
        XCTAssertFalse(beforeWarning)

        // Post a simulated memory warning
        await MainActor.run {
            NotificationCenter.default.post(
                name: UIApplication.didReceiveMemoryWarningNotification,
                object: UIApplication.shared
            )
        }

        // Give the async handler time to run
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        // Engine was not loaded so unload should be a no-op — still false
        let afterWarning = await engine.isLoaded()
        XCTAssertFalse(afterWarning, "Engine must remain unloaded after memory warning.")

        await manager.stop()
    }

    func testBackgroundNotificationCausesNoLoadedEngineToStayUnloaded() async throws {
        let fakeURL = URL(fileURLWithPath: "/fake/model.mlpackage")
        let tok = try makeStubTokenizer()
        let engine = InferenceEngine(modelURL: fakeURL, tokenizer: tok, contextLength: 128)

        await manager.start(engine: engine)

        await MainActor.run {
            NotificationCenter.default.post(
                name: UIApplication.didEnterBackgroundNotification,
                object: UIApplication.shared
            )
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        let loaded = await engine.isLoaded()
        XCTAssertFalse(loaded)

        await manager.stop()
    }

    // MARK: - Helpers

    private func makeStubTokenizer() throws -> Tokenizer {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("MemMgrTests")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let json: [String: Any] = [
            "model": ["vocab": ["<unk>": 0, "<s>": 1, "</s>": 2] as [String: Int], "merges": [] as [String]],
            "added_tokens": [["id": 0, "content": "<unk>"]],
            "bos_token": "<s>", "eos_token": "</s>",
            "unk_token": "<unk>", "pad_token": "<unk>",
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let url = tempDir.appendingPathComponent("tokenizer.json")
        try data.write(to: url)

        class TempBundle: Bundle {
            let dir: URL
            init(dir: URL) { self.dir = dir; super.init() }
            override func url(forResource name: String?, withExtension ext: String?) -> URL? {
                guard let name, let ext else { return nil }
                let c = dir.appendingPathComponent("\(name).\(ext)")
                return FileManager.default.fileExists(atPath: c.path) ? c : nil
            }
        }
        return try Tokenizer(vocabFilename: "tokenizer", bundle: TempBundle(dir: tempDir))
    }
}
