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

/// A single decoded token emitted by `InferenceEngine.generate()`.
struct InferenceToken: Sendable {
    /// Decoded text fragment (may be a sub-word piece, e.g. "▁hel" or "lo").
    let text: String
    /// Raw vocabulary integer ID.
    let tokenId: Int
    /// `true` on the terminal sentinel — no more tokens will be emitted after this.
    let isFinished: Bool

    static func finished() -> InferenceToken {
        InferenceToken(text: "", tokenId: -1, isFinished: true)
    }
}

/// Metadata emitted once at the end of a generation stream alongside the finished token.
struct GenerationSummary: Sendable {
    let tokensGenerated: Int
    let timeToFirstToken: TimeInterval
    let totalTime: TimeInterval
    let tokensPerSecond: Double
    let memoryUsedBytes: Int64
    let stoppedReason: StopReason

    enum StopReason: Sendable {
        case maxTokensReached
        case endOfSequenceToken
        case cancelled
    }
}
