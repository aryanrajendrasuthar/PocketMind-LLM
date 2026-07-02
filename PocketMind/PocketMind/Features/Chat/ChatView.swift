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

import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct ChatView: View {

    @ObservedObject var viewModel: ChatViewModel
    @StateObject private var voiceInput = VoiceInputService()
    @FocusState private var inputFocused: Bool
    @State private var showSettings = false
    @State private var showFilePicker = false
    @State private var attachedFileName: String?
    @State private var attachedFileContent: String?

    var body: some View {
        // Plain VStack — no NavigationStack. iOS 26's NavigationStack reserves
        // the full liquid-glass nav-bar safe area even when .toolbar(.hidden)
        // is set, leaving a large black gap between the status bar and content.
        // SwiftUI's UIHostingController still handles keyboard avoidance and
        // safe-area insets correctly without NavigationStack.
        VStack(spacing: 0) {
            headerBar
            Divider()
            contextBanners
            messageList
            inputBar
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(item: $viewModel.pendingCapability) { capability in
            CapabilityBoundaryView(capability: capability) {
                viewModel.proceedDespiteCapabilityWarning()
            } onDismiss: {
                viewModel.dismissCapabilityWarning()
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.plainText, .pdf, .json, .commaSeparatedText, .sourceCode],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 0) {
            Button {
                viewModel.clearContext()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isGenerating)

            Spacer()

            VStack(spacing: 3) {
                Text("PocketMind")
                    .font(.system(size: 17, weight: .semibold))
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("on-device · private")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(.systemBackground))
    }

    // MARK: - Banners

    @ViewBuilder private var contextBanners: some View {
        if viewModel.contextTrimmed {
            InlineBanner(
                icon: "scissors",
                text: "Older messages removed to fit the context window.",
                color: .orange
            ) { viewModel.contextTrimmed = false }
        }
        if viewModel.memoryFreedBanner {
            InlineBanner(
                icon: "memorychip",
                text: "Memory pressure — model will reload on your next message.",
                color: .red
            ) { viewModel.memoryFreedBanner = false }
        }
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if viewModel.conversation.messages.isEmpty {
                        EmptyStateView()
                    } else {
                        ForEach(viewModel.conversation.messages) { msg in
                            MessageBubbleView(message: msg)
                        }
                        if viewModel.isGenerating {
                            if let snippet = viewModel.ragContextSnippet {
                                RAGSourceTag(snippet: snippet)
                            }
                            TypingIndicatorView()
                        }
                    }
                    // Stable bottom anchor — always rendered (VStack, not Lazy),
                    // so proxy.scrollTo("_bottom") never silently fails.
                    Color.clear.frame(height: 1).id("_bottom")
                }
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.conversation.messages.count) { _, _ in
                proxy.scrollTo("_bottom")
            }
            .onChange(of: viewModel.isGenerating) { _, generating in
                if generating { proxy.scrollTo("_bottom") }
            }
            .onChange(of: viewModel.conversation.messages.last?.content.count ?? 0) { _, _ in
                if viewModel.isGenerating { proxy.scrollTo("_bottom") }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Input bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            // Attached file chip
            if let filename = attachedFileName {
                HStack(spacing: 8) {
                    Image(systemName: "doc.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text(filename)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    Spacer()
                    Button {
                        attachedFileName = nil
                        attachedFileContent = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.08))
            }

            Divider()

            HStack(alignment: .bottom, spacing: 8) {
                // Attachment
                Button {
                    showFilePicker = true
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(.secondaryLabel))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isGenerating)

                // Voice
                Button {
                    if voiceInput.isRecording {
                        voiceInput.stopRecording()
                        if !voiceInput.transcript.isEmpty {
                            viewModel.inputText = voiceInput.transcript
                        }
                    } else {
                        Task { await voiceInput.requestPermissions() }
                        voiceInput.startRecording()
                    }
                } label: {
                    Image(systemName: voiceInput.isRecording ? "waveform.circle.fill" : "mic")
                        .font(.system(size: 20))
                        .foregroundStyle(voiceInput.isRecording ? Color.red : Color(.secondaryLabel))
                        .frame(width: 36, height: 36)
                        .symbolEffect(.pulse, isActive: voiceInput.isRecording)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isGenerating && !voiceInput.isRecording)
                .onChange(of: voiceInput.transcript) { _, transcript in
                    if !transcript.isEmpty { viewModel.inputText = transcript }
                }

                // Text field
                TextField("Message", text: $viewModel.inputText, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($inputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 22))

                // Send / Stop
                Button {
                    if viewModel.isGenerating {
                        viewModel.cancelGeneration()
                    } else {
                        sendMessage()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(sendButtonBackground)
                        Image(systemName: viewModel.isGenerating ? "stop.fill" : "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.isGenerating && !canSend)
                .animation(.easeInOut(duration: 0.15), value: viewModel.isGenerating)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .background(.ultraThinMaterial)
        }
    }

    private var sendButtonBackground: Color {
        if viewModel.isGenerating { return .red }
        return canSend ? .blue : Color(.tertiarySystemFill)
    }

    // MARK: - Helpers

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || attachedFileContent != nil
    }

    private func sendMessage() {
        inputFocused = false
        voiceInput.stopRecording()

        var text = viewModel.inputText
        let file: (name: String, content: String)?
        if let name = attachedFileName, let content = attachedFileContent {
            file = (name, content)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                text = "What can you tell me about this document?"
            }
        } else {
            file = nil
        }

        attachedFileName = nil
        attachedFileContent = nil
        viewModel.send(text: text, attachedFile: file)
    }

    // MARK: - File import

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }

        Task {
            let filename = url.lastPathComponent
            let ext = url.pathExtension.lowercased()

            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let rawText: String?
            if ext == "pdf" {
                rawText = PDFDocument(url: url)?.string
            } else {
                rawText = try? String(contentsOf: url, encoding: .utf8)
            }

            guard let text = rawText, !text.isEmpty else { return }

            let limit = 800
            let snippet: String
            if text.count > limit {
                snippet = "[File: \(filename) — first \(limit) characters]\n" + String(text.prefix(limit)) + "…"
            } else {
                snippet = "[File: \(filename)]\n" + text
            }

            await MainActor.run {
                attachedFileName = filename
                attachedFileContent = snippet
            }
        }
    }
}

// MARK: - RAG source tag

private struct RAGSourceTag: View {
    let snippet: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 10, weight: .medium))
            Text("Searching your documents…")
                .font(.system(size: 12))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Empty state

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 28) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.12), Color.purple.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                Image(systemName: "brain.head.profile.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 8) {
                Text("Your private AI")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Ask anything. No internet. No tracking.\nEverything runs on your iPhone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            HStack(spacing: 10) {
                CapabilityPill(icon: "lock.fill", label: "Private")
                CapabilityPill(icon: "iphone.gen3", label: "On-device")
                CapabilityPill(icon: "doc.text", label: "RAG")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 72)
    }
}

private struct CapabilityPill: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemBackground))
        .clipShape(Capsule())
    }
}

// MARK: - Inline banner

private struct InlineBanner: View {
    let icon: String
    let text: String
    let color: Color
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(color.opacity(0.1))
    }
}

// MARK: - QueryCapability: Identifiable for .sheet(item:)

extension QueryCapability: Identifiable {
    public var id: String {
        switch self {
        case .fullyOffline:               return "offline"
        case .requiresLiveData(let r, _): return "live-\(r)"
        case .requiresSearch(let q):      return "search-\(q)"
        }
    }
}
