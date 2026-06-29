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

// MARK: - Conversation

/// A single conversation session with its full message history.
struct Conversation: Identifiable, Codable, Sendable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    /// ID of the CoreML model used for this conversation (e.g. "pocketmind_llama32_1b-coreml").
    var modelId: String
    let createdAt: Date
    var updatedAt: Date
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        title: String = "New Conversation",
        messages: [ChatMessage] = [],
        modelId: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.modelId = modelId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
    }

    /// Total token count across all messages with known token counts.
    var totalTokenCount: Int {
        messages.compactMap(\.tokenCount).reduce(0, +)
    }
}

// MARK: - ChatMessage

/// A single message within a conversation.
struct ChatMessage: Identifiable, Codable, Sendable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date
    var tokenCount: Int?
    var inferenceMetadata: InferenceMetadata?

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        tokenCount: Int? = nil,
        inferenceMetadata: InferenceMetadata? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.tokenCount = tokenCount
        self.inferenceMetadata = inferenceMetadata
    }
}

// MARK: - MessageRole

enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

// MARK: - InferenceMetadata

/// Performance and diagnostic metadata captured during an inference run.
struct InferenceMetadata: Codable, Sendable {
    let modelId: String
    let tokensGenerated: Int
    /// Wall-clock time from `generate()` call to the first emitted token (seconds).
    let timeToFirstToken: TimeInterval
    /// Wall-clock time for the full response (seconds).
    let totalInferenceTime: TimeInterval
    let tokensPerSecond: Double
    let memoryUsedBytes: Int64
}
