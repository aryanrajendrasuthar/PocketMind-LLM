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

struct ChatView: View {

    @ObservedObject var viewModel: ChatViewModel
    @StateObject private var voiceInput = VoiceInputService()
    @FocusState private var inputFocused: Bool
    @State private var showSettings = false
    @State private var scrollProxy: ScrollViewProxy?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Banners
                if viewModel.contextTrimmed {
                    BannerView(
                        text: "Older messages were removed to fit within the model context window.",
                        color: .orange
                    ) { viewModel.contextTrimmed = false }
                }
                if viewModel.memoryFreedBanner {
                    BannerView(
                        text: "Memory pressure detected — model temporarily unloaded.",
                        color: .red
                    ) { viewModel.memoryFreedBanner = false }
                }

                // Message list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if viewModel.conversation.messages.isEmpty {
                                EmptyStateView()
                            } else {
                                ForEach(viewModel.conversation.messages) { msg in
                                    MessageBubbleView(message: msg)
                                        .id(msg.id)
                                }
                                if viewModel.isGenerating {
                                    TypingIndicatorView()
                                        .id("typing")
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onAppear { scrollProxy = proxy }
                    .onChange(of: viewModel.conversation.messages.count) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: viewModel.isGenerating) { _, generating in
                        if generating { scrollToBottom(proxy: proxy) }
                    }
                }

                // Input bar
                inputBar
            }
            .navigationTitle("PocketMind")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { viewModel.clearContext() } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(viewModel.isGenerating)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
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
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                // Voice input button
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
                    Image(systemName: voiceInput.isRecording ? "waveform.circle.fill" : "mic.circle")
                        .font(.title2)
                        .foregroundStyle(voiceInput.isRecording ? .red : .secondary)
                        .symbolEffect(.pulse, isActive: voiceInput.isRecording)
                }
                .disabled(viewModel.isGenerating)

                // Text field
                TextField("Message", text: $viewModel.inputText, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($inputFocused)
                    .onChange(of: voiceInput.transcript) { _, transcript in
                        if !transcript.isEmpty { viewModel.inputText = transcript }
                    }

                // Send / Stop
                Button {
                    if viewModel.isGenerating {
                        viewModel.cancelGeneration()
                    } else {
                        inputFocused = false
                        voiceInput.stopRecording()
                        viewModel.send(text: viewModel.inputText)
                    }
                } label: {
                    Image(systemName: viewModel.isGenerating ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(viewModel.isGenerating ? .red : .blue)
                }
                .disabled(!viewModel.isGenerating && viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
        }
    }

    // MARK: - Helpers

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if viewModel.isGenerating {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let last = viewModel.conversation.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Empty state

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.filled.head.profile")
                .font(.system(size: 56))
                .foregroundStyle(.blue.opacity(0.4))
            Text("Ask me anything.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Everything runs on your device.\nNothing is shared.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
    }
}

// MARK: - Dismissible banner

private struct BannerView: View {
    let text: String
    let color: Color
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill").foregroundStyle(color)
            Text(text).font(.caption).foregroundStyle(.primary)
            Spacer()
            Button { onDismiss() } label: {
                Image(systemName: "xmark").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
    }
}

// MARK: - QueryCapability: Identifiable for .sheet(item:)

extension QueryCapability: Identifiable {
    public var id: String {
        switch self {
        case .fullyOffline:              return "offline"
        case .requiresLiveData(let r, _): return "live-\(r)"
        case .requiresSearch(let q):     return "search-\(q)"
        }
    }
}
