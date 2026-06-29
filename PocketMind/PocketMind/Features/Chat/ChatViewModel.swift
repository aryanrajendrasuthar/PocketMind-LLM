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
    private let vault: PrivacyVault?
    private let modelInfo: ModelInfo

    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "ChatViewModel")
    private var generationTask: Task<Void, Never>?

    // MARK: - Init

    init(modelInfo: ModelInfo) {
        self.modelInfo = modelInfo
        self.conversation = Conversation(modelId: modelInfo.id)
        self.vault = try? PrivacyVault()

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
        subscribeToMemoryNotifications()
    }

    // MARK: - Send message

    /// Classify and send a user message. If live data is needed, sets `pendingCapability`
    /// and waits for the user to confirm before proceeding.
    func send(text: String) {
        let trimmed = sanitize(text)
        guard !trimmed.isEmpty, !isGenerating else { return }

        let capability = classifier.classify(trimmed)

        switch capability {
        case .fullyOffline:
            appendUserMessage(trimmed)
            runInference(prompt: buildPrompt())
        case .requiresLiveData, .requiresSearch:
            pendingCapability = capability
            inputText = trimmed           // preserve text while sheet is shown
        }
    }

    /// Called when the user taps "Ask PocketMind anyway" in `CapabilityBoundaryView`.
    func proceedDespiteCapabilityWarning() {
        pendingCapability = nil
        let trimmed = sanitize(inputText)
        guard !trimmed.isEmpty else { return }
        appendUserMessage(trimmed)
        inputText = ""
        runInference(prompt: buildPrompt())
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

    private func runInference(prompt: String) {
        isGenerating = true
        contextTrimmed = false

        generationTask = Task {
            // Trim context if needed
            let (trimmedMessages, wasTrimmed) = await memoryManager.trimContext(
                messages: conversation.messages,
                modelContextLength: modelInfo.contextLength
            )
            if wasTrimmed {
                conversation.messages = trimmedMessages
                contextTrimmed = true
            }

            // Reserve a placeholder for the assistant turn
            conversation.messages.append(ChatMessage(role: .assistant, content: ""))
            let assistantIndex = conversation.messages.count - 1

            let start = Date()
            var firstTokenDate: Date?
            var tokenCount = 0

            let stream = await inferenceEngine.generate(
                prompt: prompt,
                maxTokens: modelInfo.maxTokens,
                temperature: UserDefaults.standard.float(forKey: "inferenceTemperature").nonZero ?? Float(Constants.Inference.defaultTemperature),
                topP: Constants.Inference.defaultTopP
            )

            for await token in stream {
                if Task.isCancelled { break }
                if token.isFinished { break }
                if firstTokenDate == nil { firstTokenDate = Date() }
                tokenCount += 1
                conversation.messages[assistantIndex].content += token.text
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

    private func buildPrompt() -> String {
        conversation.messages
            .filter { $0.role != .system }
            .map { msg in
                switch msg.role {
                case .user:      return "User: \(msg.content)"
                case .assistant: return "Assistant: \(msg.content)"
                case .system:    return msg.content
                }
            }
            .joined(separator: "\n")
            + "\nAssistant:"
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
            self?.memoryFreedBanner = true
        }
        NotificationCenter.default.addObserver(
            forName: MemoryManager.contextTrimmedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.contextTrimmed = true
        }
    }
}

// MARK: - Tokenizer placeholder

extension Tokenizer {
    /// Returns a non-functional placeholder for builds where the vocab file isn't bundled yet.
    static func placeholder() -> Tokenizer {
        (try? Tokenizer()) ?? {
            fatalError("Tokenizer could not be initialized. Ensure tokenizer.json is in the bundle.")
        }()
    }
}

// MARK: - Float extension

private extension Float {
    var nonZero: Float? { self == 0 ? nil : self }
}
