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
/// User: right-aligned, filled blue bubble.
/// Assistant: left-aligned, no background, code blocks in monospace.
struct MessageBubbleView: View {

    let message: ChatMessage
    @State private var showMetadata = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user { Spacer(minLength: 48) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                contentView
                    .padding(message.role == .user ? .horizontal : [])
                    .padding(message.role == .user ? .vertical : [])
                    .background(message.role == .user ? Color.blue : Color.clear)
                    .foregroundStyle(message.role == .user ? .white : Color(.label))
                    .clipShape(BubbleShape(isUser: message.role == .user))

                if let meta = message.inferenceMetadata, message.role == .assistant {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showMetadata.toggle() }
                    } label: {
                        Text(String(format: "%.1f tok/s", meta.tokensPerSecond))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)

                    if showMetadata {
                        Text(String(format: "%d tokens · %.2fs TTFT · %@ model",
                                    meta.tokensGenerated,
                                    meta.timeToFirstToken,
                                    modelShortName(meta.modelId)))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .transition(.opacity)
                    }
                }
            }

            if message.role != .user { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }

    // MARK: - Content rendering

    @ViewBuilder
    private var contentView: some View {
        if message.role == .assistant {
            // Render code blocks in monospace, prose in body font
            FormattedTextView(text: message.content)
        } else {
            Text(message.content)
                .font(.body)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
    }

    private func modelShortName(_ modelId: String) -> String {
        if modelId.contains("1b") { return "Llama 1B" }
        if modelId.contains("3b") { return "Llama 3B" }
        if modelId.contains("phi") { return "Phi-3" }
        return modelId
    }
}

// MARK: - Bubble shape

private struct BubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 18
        let tail: CGFloat = 6
        var path = Path()

        if isUser {
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
                        radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r - tail))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                        radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
                        radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r),
                        radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        } else {
            path = Path(RoundedRectangle(cornerRadius: r).path(in: rect))
        }
        path.closeSubpath()
        return path
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
                        .font(.system(.body, design: .monospaced))
                        .padding(10)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .textSelection(.enabled)
                } else {
                    Text(segment.content)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
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
