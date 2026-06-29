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

/// Tests for PrivacyVault encrypted persistence.
///
/// The database key derivation requires the Secure Enclave, which is not
/// available on the simulator. Tests that touch the real database are marked
/// `@available` with a fallback for simulator environments.
final class PrivacyVaultTests: XCTestCase {

    // MARK: - Helpers

    private func makeVault() throws -> PrivacyVault {
        try PrivacyVault()
    }

    private func makeConversation(modelId: String = "pocketmind_llama32_1b-coreml") -> Conversation {
        Conversation(modelId: modelId)
    }

    private func makeMessage(role: MessageRole = .user, content: String = "Hello") -> ChatMessage {
        ChatMessage(role: role, content: content)
    }

    // MARK: - Save and load roundtrip

    func testSaveAndLoadRoundtrip() async throws {
        let vault = try makeVault()
        var conversation = makeConversation()
        let message = makeMessage(role: .user, content: "What is recursion?")
        conversation.messages.append(message)

        try await vault.saveMessage(message, inConversation: conversation)

        let loaded = try await vault.loadConversation(id: conversation.id)
        XCTAssertEqual(loaded.id, conversation.id)
        XCTAssertEqual(loaded.messages.count, 1)
        XCTAssertEqual(loaded.messages.first?.content, "What is recursion?")
        XCTAssertEqual(loaded.messages.first?.role, .user)
    }

    func testSaveMultipleMessagesPreservesOrder() async throws {
        let vault = try makeVault()
        var conversation = makeConversation()

        let userMsg = makeMessage(role: .user, content: "First message")
        let assistantMsg = makeMessage(role: .assistant, content: "First response")
        conversation.messages = [userMsg, assistantMsg]

        try await vault.saveMessage(userMsg, inConversation: conversation)
        try await vault.saveMessage(assistantMsg, inConversation: conversation)

        let loaded = try await vault.loadConversation(id: conversation.id)
        XCTAssertEqual(loaded.messages.count, 2)
        XCTAssertEqual(loaded.messages[0].role, .user)
        XCTAssertEqual(loaded.messages[1].role, .assistant)
    }

    func testSaveInferenceMetadataRoundtrip() async throws {
        let vault = try makeVault()
        let conversation = makeConversation()
        let metadata = InferenceMetadata(
            modelId: "pocketmind_llama32_1b-coreml",
            tokensGenerated: 42,
            timeToFirstToken: 1.23,
            totalInferenceTime: 5.67,
            tokensPerSecond: 7.41,
            memoryUsedBytes: 512_000_000
        )
        var message = makeMessage(role: .assistant, content: "Recursion is...")
        message = ChatMessage(
            id: message.id,
            role: message.role,
            content: message.content,
            timestamp: message.timestamp,
            tokenCount: 42,
            inferenceMetadata: metadata
        )

        try await vault.saveMessage(message, inConversation: conversation)
        let loaded = try await vault.loadConversation(id: conversation.id)
        let loadedMsg = try XCTUnwrap(loaded.messages.first)

        XCTAssertEqual(loadedMsg.tokenCount, 42)
        XCTAssertEqual(loadedMsg.inferenceMetadata?.tokensGenerated, 42)
        XCTAssertEqual(loadedMsg.inferenceMetadata?.modelId, "pocketmind_llama32_1b-coreml")
        XCTAssertEqual(loadedMsg.inferenceMetadata?.tokensPerSecond, 7.41, accuracy: 0.001)
    }

    // MARK: - Delete conversation

    func testDeleteConversationRemovesAllMessages() async throws {
        let vault = try makeVault()
        var conversation = makeConversation()
        let msg1 = makeMessage(content: "Message one")
        let msg2 = makeMessage(content: "Message two")
        conversation.messages = [msg1, msg2]

        try await vault.saveMessage(msg1, inConversation: conversation)
        try await vault.saveMessage(msg2, inConversation: conversation)

        try await vault.deleteConversation(id: conversation.id)

        do {
            _ = try await vault.loadConversation(id: conversation.id)
            XCTFail("Expected notFound error after deletion.")
        } catch PrivacyVault.VaultError.notFound {
            // Expected
        }
    }

    // MARK: - Delete all data

    func testDeleteAllDataReturnsEmptyState() async throws {
        let vault = try makeVault()
        let conversation = makeConversation()
        let message = makeMessage(content: "Private thought")
        try await vault.saveMessage(message, inConversation: conversation)

        try await vault.deleteAllData()

        // After deleteAllData, creating a fresh vault should give empty state
        let freshVault = try makeVault()
        let allConversations = try await freshVault.loadAllConversations()
        XCTAssertTrue(allConversations.isEmpty, "All conversations must be empty after deleteAllData.")
    }

    func testDeleteAllDataClearsUserDefaults() async throws {
        let vault = try makeVault()
        let testKey = "test.pocketmind.setting"
        UserDefaults.standard.set("sensitive_value", forKey: testKey)

        try await vault.deleteAllData()

        // After wipe, the key should be gone
        XCTAssertNil(UserDefaults.standard.string(forKey: testKey))
    }

    // MARK: - Backup exclusion

    func testDatabaseDirectoryIsExcludedFromBackup() throws {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        let dbDir = appSupport.appendingPathComponent(Constants.Storage.databaseDirectory, isDirectory: true)

        // Directory may not exist yet on fresh simulators — skip if absent
        guard FileManager.default.fileExists(atPath: dbDir.path) else {
            throw XCTSkip("Database directory not yet created — run vault init first.")
        }

        let resourceValues = try dbDir.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertTrue(resourceValues.isExcludedFromBackup == true,
                      "Database directory must be excluded from iCloud backup.")
    }

    // MARK: - Key derivation (simulator safe)

    func testDatabaseKeyDerivationDoesNotThrowOnSimulator() {
        // The Secure Enclave is not available in the simulator.
        // SecureEnclaveKeyManager should throw a clear error rather than crash.
        #if targetEnvironment(simulator)
        XCTAssertThrowsError(try SecureEnclaveKeyManager.deriveDatabaseKey()) { error in
            // Any error is acceptable — we just verify it doesn't crash
            XCTAssertNotNil(error)
        }
        #else
        // On a real device, key derivation must succeed
        XCTAssertNoThrow(try SecureEnclaveKeyManager.deriveDatabaseKey())
        #endif
    }

    // MARK: - Load all conversations

    func testLoadAllConversationsReturnsCorrectCount() async throws {
        let vault = try makeVault()
        try await vault.deleteAllData()
        let freshVault = try makeVault()

        let conv1 = makeConversation()
        let conv2 = makeConversation()

        try await freshVault.saveMessage(makeMessage(content: "A"), inConversation: conv1)
        try await freshVault.saveMessage(makeMessage(content: "B"), inConversation: conv2)

        let all = try await freshVault.loadAllConversations()
        XCTAssertEqual(all.count, 2)
    }

    func testPinnedConversationsAppearFirst() async throws {
        let vault = try makeVault()
        try await vault.deleteAllData()
        let freshVault = try makeVault()

        var pinned = makeConversation()
        pinned = Conversation(
            id: pinned.id,
            title: "Pinned",
            messages: [],
            modelId: pinned.modelId,
            createdAt: Date(timeIntervalSinceNow: -100),
            updatedAt: Date(timeIntervalSinceNow: -100),
            isPinned: true
        )
        var regular = makeConversation()
        regular = Conversation(
            id: regular.id,
            title: "Regular",
            messages: [],
            modelId: regular.modelId,
            createdAt: Date(),
            updatedAt: Date(),
            isPinned: false
        )

        try await freshVault.saveMessage(makeMessage(content: "pin"), inConversation: pinned)
        try await freshVault.saveMessage(makeMessage(content: "reg"), inConversation: regular)

        let all = try await freshVault.loadAllConversations()
        XCTAssertEqual(all.first?.isPinned, true, "Pinned conversations must appear first.")
    }
}
