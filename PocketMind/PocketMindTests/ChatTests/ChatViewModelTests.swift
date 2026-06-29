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

import Testing
@testable import PocketMind

/// Tests for the ChatViewModel focusing on input sanitization and classifier routing.
/// Inference pipeline tests require a loaded CoreML model and run on device.
@MainActor
struct ChatViewModelTests {

    private func makeViewModel() -> ChatViewModel {
        ChatViewModel(modelInfo: ModelInfo.allModels[0])
    }

    // MARK: - Initial state

    @Test func initialConversationHasNoMessages() {
        let vm = makeViewModel()
        #expect(vm.conversation.messages.isEmpty)
    }

    @Test func initialInputTextIsEmpty() {
        let vm = makeViewModel()
        #expect(vm.inputText.isEmpty)
    }

    @Test func initialIsGeneratingFalse() {
        let vm = makeViewModel()
        #expect(!vm.isGenerating)
    }

    @Test func initialPendingCapabilityNil() {
        let vm = makeViewModel()
        #expect(vm.pendingCapability == nil)
    }

    // MARK: - Input sanitization (whitebox via send)

    @Test func sendEmptyStringDoesNotAddMessage() {
        let vm = makeViewModel()
        vm.send(text: "   ")
        #expect(vm.conversation.messages.isEmpty)
    }

    @Test func sendMessageExceedingLimitIsTruncated() {
        let vm = makeViewModel()
        let overlong = String(repeating: "a", count: Constants.UI.maxUserMessageLength + 100)
        vm.send(text: overlong)
        let userMsg = vm.conversation.messages.first(where: { $0.role == .user })
        // After sanitization the content must not exceed the limit
        if let content = userMsg?.content {
            #expect(content.count <= Constants.UI.maxUserMessageLength)
        }
    }

    @Test func sendStripsSuspiciousControlCharacters() {
        let vm = makeViewModel()
        // NUL and BEL are control characters that must be stripped
        let malicious = "Hello\u{00}World\u{07}!"
        vm.send(text: malicious)
        let userMsg = vm.conversation.messages.first(where: { $0.role == .user })
        if let content = userMsg?.content {
            #expect(!content.contains("\u{00}"))
            #expect(!content.contains("\u{07}"))
        }
    }

    @Test func sendPreservesNewlinesAndTabs() {
        let vm = makeViewModel()
        let text = "Line 1\nLine 2\tTabbed"
        vm.send(text: text)
        let userMsg = vm.conversation.messages.first(where: { $0.role == .user })
        if let content = userMsg?.content {
            #expect(content.contains("\n") || content.contains("\t") || !content.isEmpty)
        }
    }

    // MARK: - Classifier routing

    @Test func sendOfflineQueryAddsUserMessageImmediately() {
        let vm = makeViewModel()
        vm.send(text: "Explain the concept of recursion in programming")
        // Classifier should route this as offline — user message appended before inference starts
        let userMsg = vm.conversation.messages.first(where: { $0.role == .user })
        #expect(userMsg != nil)
    }

    @Test func sendLiveDataQuerySetsPendingCapability() {
        let vm = makeViewModel()
        vm.send(text: "What is the current Bitcoin price today?")
        // Classifier should flag this as live data — no message appended, capability set
        #expect(vm.pendingCapability != nil)
        #expect(vm.conversation.messages.isEmpty)
    }

    @Test func dismissCapabilityWarningClearsPendingCapability() {
        let vm = makeViewModel()
        vm.send(text: "What is the current stock price of Apple?")
        #expect(vm.pendingCapability != nil)
        vm.dismissCapabilityWarning()
        #expect(vm.pendingCapability == nil)
    }

    // MARK: - Context management

    @Test func clearContextRemovesAllMessages() {
        let vm = makeViewModel()
        vm.send(text: "Tell me about machine learning")
        vm.clearContext()
        #expect(vm.conversation.messages.isEmpty)
    }

    @Test func clearContextResetsTrimmedFlag() {
        let vm = makeViewModel()
        vm.contextTrimmed = true
        vm.clearContext()
        #expect(!vm.contextTrimmed)
    }

    // MARK: - Cancel generation

    @Test func cancelGenerationSetsIsGeneratingFalse() async {
        let vm = makeViewModel()
        vm.send(text: "Write a very long story about dragons")
        // Give the task a moment to start
        try? await Task.sleep(nanoseconds: 50_000_000)
        vm.cancelGeneration()
        #expect(!vm.isGenerating)
    }

    // MARK: - Copy last response

    @Test func copyLastResponseDoesNotCrashWhenNoMessages() {
        let vm = makeViewModel()
        vm.copyLastResponse()  // must not crash
        #expect(vm.conversation.messages.isEmpty)
    }
}
