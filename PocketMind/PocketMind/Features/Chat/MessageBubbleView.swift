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

/// Renders a single chat message bubble.
/// User: right-aligned, filled blue, white text.
/// Assistant: left-aligned, system secondary background, adapts to dark mode.
struct MessageBubbleView: View {

    let message: ChatMessage
    @State private var showMetadata = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if message.role == .user { Spacer(minLength: 56) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 5) {
                messageBubble
                metadataLine
            }

            if message.role != .user { Spacer(minLength: 56) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
    }

    // MARK: - Bubble

    @ViewBuilder
    private var messageBubble: some View {
        if message.role == .user {
            Text(message.content)
                .font(.body)
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 20))
        } else {
            FormattedTextView(text: message.content)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: - Metadata (tap to expand)

    @ViewBuilder
    private var metadataLine: some View {
        if let meta = message.inferenceMetadata, message.role == .assistant {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showMetadata.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9))
                    if showMetadata {
                        Text("\(meta.tokensGenerated) tokens · \(String(format: "%.1f", meta.tokensPerSecond)) tok/s · \(String(format: "%.2f", meta.timeToFirstToken))s TTFT · \(modelShortName(meta.modelId))")
                    } else {
                        Text(String(format: "%.1f tok/s", meta.tokensPerSecond))
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            .animation(.easeInOut(duration: 0.18), value: showMetadata)
        }
    }

    private func modelShortName(_ modelId: String) -> String {
        if modelId.contains("1b") { return "Llama 1B" }
        if modelId.contains("3b") { return "Llama 3B" }
        if modelId.contains("phi") { return "Phi-3" }
        return modelId
    }
}

// MARK: - Formatted text (code block detection)

private struct FormattedTextView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(segments(from: text), id: \.id) { segment in
                if segment.isCode {
                    Text(segment.content)
                        .font(.system(.callout, design: .monospaced))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.quaternarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .textSelection(.enabled)
                } else {
                    Text(segment.content)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private struct Segment: Identifiable {
        let id = UUID()
        let content: String
        let isCode: Bool
    }

    private func segments(from text: String) -> [Segment] {
        var result: [Segment] = []
        var remaining = text
        while !remaining.isEmpty {
            if let codeRange = remaining.range(of: "```") {
                let before = String(remaining[remaining.startIndex..<codeRange.lowerBound])
                if !before.isEmpty { result.append(Segment(content: before, isCode: false)) }
                remaining = String(remaining[codeRange.upperBound...])
                if let endRange = remaining.range(of: "```") {
                    let code = String(remaining[remaining.startIndex..<endRange.lowerBound])
                    result.append(Segment(content: code.trimmingCharacters(in: .newlines), isCode: true))
                    remaining = String(remaining[endRange.upperBound...])
                } else {
                    result.append(Segment(content: remaining, isCode: true))
                    remaining = ""
                }
            } else {
                result.append(Segment(content: remaining, isCode: false))
                remaining = ""
            }
        }
        return result
    }
}
