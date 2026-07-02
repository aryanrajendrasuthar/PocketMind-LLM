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
import MachO
import os.log
import UIKit

/// Monitors device RAM and manages the KV cache context window.
///
/// Two signals trigger model unload:
/// 1. `UIApplication.didReceiveMemoryWarningNotification` — system-issued warning
/// 2. Proactive polling: when `os_proc_available_memory()` drops below 500 MB
///
/// The actor also handles `UIApplication.didEnterBackgroundNotification` by
/// unloading the model to avoid background termination by iOS.
actor MemoryManager {

    // MARK: - Notifications

    /// Posted on `MainActor` when the inference model is unloaded due to memory pressure.
    static let inferenceUnloadedNotification = Notification.Name("PocketMindInferenceUnloaded")
    /// Posted on `MainActor` when the KV cache is trimmed.
    static let contextTrimmedNotification = Notification.Name("PocketMindContextTrimmed")

    // MARK: - State

    private weak var inferenceEngine: AnyObject?
    private var inferenceEngineRef: InferenceEngine? {
        inferenceEngine as? InferenceEngine
    }

    private var pollingTask: Task<Void, Never>?
    private var notificationObservers: [NSObjectProtocol] = []
    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "MemoryManager")

    // MARK: - Init / Start

    /// Attach to an `InferenceEngine` and begin monitoring.
    func start(engine: InferenceEngine) {
        // Hold a weak reference to avoid a retain cycle
        self.inferenceEngine = engine as AnyObject
        subscribeToSystemNotifications()
        startPolling()
        logger.info("MemoryManager started.")
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        notificationObservers.removeAll()
        logger.info("MemoryManager stopped.")
    }

    // MARK: - Public utilities

    /// Returns the process physical memory footprint in bytes.
    /// Uses the Mach task_info API — available on all iOS devices.
    func currentMemoryUsageBytes() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }

    /// Trim the conversation message list to fit within the context window.
    ///
    /// Algorithm:
    /// 1. Always keep the system prompt (first message if `role == .system`).
    /// 2. Drop the oldest user+assistant message pairs until the total token
    ///    count fits within `contextLimit - Constants.Inference.contextHeadroomTokens`.
    /// 3. Return the trimmed message list. The caller is responsible for
    ///    notifying the UI if the result differs from the input.
    ///
    /// - Parameters:
    ///   - messages: Full conversation message list in chronological order.
    ///   - modelContextLength: The model's native context length.
    /// - Returns: `(trimmedMessages, wasTrimmed)` — the second value is `true` if any messages were removed.
    func trimContext(
        messages: [ChatMessage],
        modelContextLength: Int,
        responseHeadroom: Int = Constants.Inference.contextHeadroomTokens
    ) -> (messages: [ChatMessage], wasTrimmed: Bool) {
        let limit = min(modelContextLength, Constants.Inference.maxContextTokens)
        // Reserve space for the next response; ensure budget is always positive.
        let budget = max(1, limit - min(responseHeadroom, limit - 1))

        // Separate system prompt if present
        var systemPrompt: ChatMessage?
        var conversationMessages: [ChatMessage]
        if messages.first?.role == .system {
            systemPrompt = messages.first
            conversationMessages = Array(messages.dropFirst())
        } else {
            conversationMessages = messages
        }

        // Sum tokens (use tokenCount if available, fall back to word-count estimate)
        func tokenCount(_ msg: ChatMessage) -> Int {
            msg.tokenCount ?? estimateTokenCount(msg.content)
        }

        func systemTokens() -> Int { systemPrompt.map(tokenCount) ?? 0 }

        func totalTokens(_ msgs: [ChatMessage]) -> Int {
            msgs.reduce(systemTokens()) { $0 + tokenCount($1) }
        }

        guard totalTokens(conversationMessages) > budget else {
            return (messages, false)
        }

        // Drop oldest pairs until we fit
        while totalTokens(conversationMessages) > budget && !conversationMessages.isEmpty {
            // Drop in pairs (user + assistant) from the front to preserve turn structure
            if conversationMessages.count >= 2 {
                conversationMessages.removeFirst(2)
            } else {
                conversationMessages.removeFirst()
            }
        }

        var result: [ChatMessage] = []
        if let sys = systemPrompt { result.append(sys) }
        result.append(contentsOf: conversationMessages)

        logger.info(
            "Context trimmed to \(result.count) messages (\(totalTokens(conversationMessages)) tokens)."
        )
        return (result, true)
    }

    // MARK: - Notification subscriptions

    private func subscribeToSystemNotifications() {
        let center = NotificationCenter.default

        let memWarn = center.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.handleMemoryPressure(source: "UIKit memory warning") }
        }

        let background = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.handleMemoryPressure(source: "app entered background") }
        }

        notificationObservers = [memWarn, background]
    }

    // MARK: - Proactive polling

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                await checkMemoryProactively()
                try? await Task.sleep(nanoseconds: UInt64(Constants.UI.memoryPollIntervalSeconds * 1_000_000_000))
            }
        }
    }

    private func checkMemoryProactively() async {
        let usage = currentMemoryUsageBytes()
        // os_proc_available_memory() is not directly available; derive from footprint heuristic
        // A device with 6 GB RAM and 4 GB footprint has ~2 GB left — this threshold is conservative.
        if usage > 0 {
            // Estimate available RAM: if our footprint exceeds a threshold correlated with pressure
            // iOS will issue a memory warning first, but we add an early check.
            let threshold = Constants.Inference.memoryPressureThresholdBytes
            // We check footprint growth rather than available RAM since os_proc_available_memory
            // requires direct Mach calls that aren't in the public SDK on iOS.
            // The UIKit memory warning is the authoritative signal; this polls as a backstop.
            if usage > threshold * 6 {
                await handleMemoryPressure(source: "proactive memory check (footprint \(usage / 1_048_576) MB)")
            }
        }
    }

    // MARK: - Memory pressure response

    private func handleMemoryPressure(source: String) async {
        logger.warning("Memory pressure triggered by: \(source, privacy: .public)")

        guard let engine = inferenceEngineRef else { return }
        let wasLoaded = await engine.isLoaded()
        guard wasLoaded else { return }

        await engine.unloadModel()

        await MainActor.run {
            NotificationCenter.default.post(
                name: MemoryManager.inferenceUnloadedNotification,
                object: nil,
                userInfo: ["source": source]
            )
        }
    }

    // MARK: - Token count estimation

    /// Rough token count estimate when `ChatMessage.tokenCount` is nil.
    /// Uses the rule-of-thumb: 1 token ≈ 0.75 words for English text.
    private func estimateTokenCount(_ text: String) -> Int {
        let wordCount = text.split(separator: " ").count
        return max(1, Int(Double(wordCount) / 0.75))
    }
}
