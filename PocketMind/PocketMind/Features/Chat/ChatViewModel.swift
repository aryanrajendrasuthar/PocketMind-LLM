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
import UIKit

/// Drives the chat interface: capability classification, inference, context trimming,
/// and encrypted persistence.
@MainActor
final class ChatViewModel: ObservableObject {

    // MARK: - Published state

    @Published var conversation: Conversation
    @Published var inputText = ""
    @Published var isGenerating = false
    @Published var pendingCapability: QueryCapability?   // non-nil triggers CapabilityBoundaryView
    @Published var contextTrimmed = false                // true → show "older messages removed" banner
    @Published var memoryFreedBanner = false             // true → show "freeing memory" banner
    @Published var errorMessage: String?

    // MARK: - Dependencies

    private let inferenceEngine: InferenceEngine
    private let memoryManager: MemoryManager
    private let classifier = CapabilityBoundaryClassifier()
    private var vault: PrivacyVault?
    private let modelInfo: ModelInfo
    let ragEngine = RAGEngine()

    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "ChatViewModel")
    private var generationTask: Task<Void, Never>?

    // MARK: - Published RAG state

    /// Most recent RAG context injected into the prompt, for display in the UI.
    @Published var ragContextSnippet: String?

    // MARK: - Init

    init(modelInfo: ModelInfo) {
        self.modelInfo = modelInfo
        self.conversation = Conversation(modelId: modelInfo.id)
        self.vault = nil

        let modelURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Constants.Storage.modelsDirectory)
            .appendingPathComponent(modelInfo.id)

        let tokenizer = (try? Tokenizer()) ?? Tokenizer.placeholder()
        self.inferenceEngine = InferenceEngine(
            modelURL: modelURL,
            tokenizer: tokenizer,
            contextLength: modelInfo.contextLength
        )
        self.memoryManager = MemoryManager()

        Task { await memoryManager.start(engine: inferenceEngine) }
        Task { @MainActor [weak self] in self?.vault = try? await PrivacyVault() }
        // Load the model in the background immediately so first-message latency is
        // just generation time, not compilation + load time.
        Task(priority: .background) { try? await inferenceEngine.loadModel() }
        subscribeToMemoryNotifications()
    }

    // MARK: - Send message

    /// Send a message and optionally index an attached file into the RAG store first.
    func send(text: String, attachedFile: (name: String, content: String)? = nil) {
        let trimmed = sanitize(text)
        guard !trimmed.isEmpty, !isGenerating else { return }

        let capability = classifier.classify(trimmed)

        switch capability {
        case .fullyOffline:
            appendUserMessage(trimmed)
            runInference(fileToIndex: attachedFile)
        case .requiresLiveData, .requiresSearch:
            pendingCapability = capability
            inputText = trimmed
        }
    }

    /// Called when the user taps "Ask PocketMind anyway" in `CapabilityBoundaryView`.
    func proceedDespiteCapabilityWarning() {
        pendingCapability = nil
        let trimmed = sanitize(inputText)
        guard !trimmed.isEmpty else { return }
        appendUserMessage(trimmed)
        inputText = ""
        runInference()
    }

    func dismissCapabilityWarning() {
        pendingCapability = nil
    }

    /// Cancel an in-progress generation.
    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
    }

    /// Clear all messages but keep the conversation record (new context).
    func clearContext() {
        conversation.messages.removeAll()
        contextTrimmed = false
    }

    /// Copy the last assistant response to the pasteboard.
    func copyLastResponse() {
        let text = conversation.messages.last(where: { $0.role == .assistant })?.content ?? ""
        UIPasteboard.general.string = text
    }

    // MARK: - Inference

    private func runInference(fileToIndex: (name: String, content: String)? = nil) {
        isGenerating = true
        contextTrimmed = false
        ragContextSnippet = nil

        generationTask = Task {
            // Index the attached document BEFORE retrieval so RAG can find it
            // on the very first question after attachment (no race condition).
            if let file = fileToIndex {
                await ragEngine.indexDocument(filename: file.name, content: file.content)
            }

            // Retrieve RAG context for the last user message before trimming, so the
            // retrieved passage is NOT counted against conversation history budget.
            let lastUserText = conversation.messages.last(where: { $0.role == .user })?.content ?? ""
            var ragContext = await ragEngine.retrieveContext(for: lastUserText)

            // When a file was just indexed but the query is too generic to match any chunk
            // above the similarity threshold (e.g. "Understand this document"), inject
            // the raw file content directly so the model always has context about the attachment.
            if ragContext == nil, let file = fileToIndex {
                let snippet = String(file.content.prefix(240))
                if !snippet.isEmpty { ragContext = snippet }
            }

            if let ctx = ragContext {
                ragContextSnippet = ctx
            }

            // Trim conversation history to leave room for the response.
            let (trimmedMessages, wasTrimmed) = await memoryManager.trimContext(
                messages: conversation.messages,
                modelContextLength: modelInfo.contextLength,
                responseHeadroom: 100  // reduced from maxTokens=200 to leave room for RAG
            )
            if wasTrimmed {
                conversation.messages = trimmedMessages
                contextTrimmed = true
            }

            // Build prompt AFTER trimming so the model only sees what fits.
            let prompt = buildPrompt(ragContext: ragContext)

            // Reserve a placeholder for the assistant turn
            conversation.messages.append(ChatMessage(role: .assistant, content: ""))
            let assistantIndex = conversation.messages.count - 1

            let start = Date()
            var firstTokenDate: Date?
            var tokenCount = 0

            let stream = await inferenceEngine.generate(
                prompt: prompt,
                maxTokens: modelInfo.maxTokens,
                temperature: UserDefaults.standard.float(forKey: "inferenceTemperature").nonZero ?? Constants.Inference.defaultTemperature,
                topP: Float(UserDefaults.standard.double(forKey: "inferenceTopP")).nonZero ?? Constants.Inference.defaultTopP
            )

            // Batch token text: update the @Published property every 3 tokens instead of
            // every single token. This cuts SwiftUI re-render frequency by ~3×, reducing
            // main-thread load without visibly affecting streaming latency at 1 tok/s.
            var tokenBuffer = ""
            var batchCount = 0
            for await token in stream {
                if Task.isCancelled { break }
                if token.isFinished { break }
                if firstTokenDate == nil { firstTokenDate = Date() }
                tokenCount += 1
                tokenBuffer += token.text
                batchCount += 1
                if batchCount >= 3 {
                    conversation.messages[assistantIndex].content += tokenBuffer
                    tokenBuffer = ""
                    batchCount = 0
                }
            }
            if !tokenBuffer.isEmpty {
                conversation.messages[assistantIndex].content += tokenBuffer
            }

            let totalTime = Date().timeIntervalSince(start)
            let ttft = firstTokenDate.map { $0.timeIntervalSince(start) } ?? totalTime

            // Attach metadata
            conversation.messages[assistantIndex].tokenCount = tokenCount
            conversation.messages[assistantIndex].inferenceMetadata = InferenceMetadata(
                modelId: modelInfo.id,
                tokensGenerated: tokenCount,
                timeToFirstToken: ttft,
                totalInferenceTime: totalTime,
                tokensPerSecond: tokenCount > 0 ? Double(tokenCount) / totalTime : 0,
                memoryUsedBytes: await memoryManager.currentMemoryUsageBytes()
            )

            // Persist
            if let vault {
                try? await vault.saveMessage(conversation.messages[assistantIndex],
                                             inConversation: conversation)
            }

            isGenerating = false
        }
    }

    // MARK: - Helpers

    private func appendUserMessage(_ text: String) {
        let msg = ChatMessage(role: .user, content: text)
        conversation.messages.append(msg)
        inputText = ""
        if let vault { Task { try? await vault.saveMessage(msg, inConversation: conversation) } }
    }

    private func buildPrompt(ragContext: String? = nil) -> String {
        // System prompt: 15 tokens max to preserve the 256-token context budget.
        let systemText = "Answer concisely. Say \"I'm not sure\" if uncertain."

        var result = "<|begin_of_text|>"
        result += "<|start_header_id|>system<|end_header_id|>\n\n\(systemText)<|eot_id|>"

        let messages = conversation.messages.filter { $0.role != .system }
        // Pre-compute so we don't scan the array on every iteration.
        let lastUserIdx = messages.indices.last { messages[$0].role == .user }

        for (i, msg) in messages.enumerated() {
            switch msg.role {
            case .user:
                var content = msg.content
                // Inject retrieved context only into the last user turn — this keeps it
                // at the end of the token sequence so it is never truncated by context overflow.
                if i == lastUserIdx, let ctx = ragContext {
                    content = "\(Constants.RAG.contextPrefix)\(ctx)\n\nQuestion: \(content)"
                }
                result += "<|start_header_id|>user<|end_header_id|>\n\n\(content)<|eot_id|>"
            case .assistant where !msg.content.isEmpty:
                result += "<|start_header_id|>assistant<|end_header_id|>\n\n\(msg.content)<|eot_id|>"
            default:
                break
            }
        }
        result += "<|start_header_id|>assistant<|end_header_id|>\n\n"
        return result
    }

    /// Strip control characters (security: prevent prompt injection).
    private func sanitize(_ text: String) -> String {
        let clipped = String(text.prefix(Constants.UI.maxUserMessageLength))
        return clipped.unicodeScalars
            .filter { $0.value >= 0x20 || $0.value == 0x0A || $0.value == 0x09 }
            .map(String.init)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func subscribeToMemoryNotifications() {
        NotificationCenter.default.addObserver(
            forName: MemoryManager.inferenceUnloadedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.memoryFreedBanner = true }
        }
        NotificationCenter.default.addObserver(
            forName: MemoryManager.contextTrimmedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.contextTrimmed = true }
        }
    }
}

// MARK: - Tokenizer placeholder

extension Tokenizer {
    /// Returns a non-functional placeholder for builds where the vocab file isn't bundled yet.
    static func placeholder() -> Tokenizer {
        (try? Tokenizer()) ?? Tokenizer(
            vocab: [:], reverseVocab: [:], merges: [],
            bosTokenId: 1, eosTokenId: 2, unkTokenId: 0, padTokenId: 0
        )
    }
}

// MARK: - Float extension

private extension Float {
    var nonZero: Float? { self == 0 ? nil : self }
}
