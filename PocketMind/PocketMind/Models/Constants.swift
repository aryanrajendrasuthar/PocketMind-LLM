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

/// Central namespace for all compile-time constants.
/// Never hardcode these values inline — always reference this file.
enum Constants {

    // MARK: - App

    static let bundleIdentifier = "com.aryan.pocketmind"
    static let appVersion = "1.0.0"

    // MARK: - Keychain

    enum Keychain {
        static let secureEnclaveKeyTag = "com.aryan.pocketmind.dbkey"
        static let accessGroup = "com.aryan.pocketmind"
    }

    // MARK: - Storage directories

    enum Storage {
        /// Encrypted SQLCipher conversation database.
        static let databaseFilename = "pocketmind.db"
        /// Subdirectory inside Application Support for the database.
        static let databaseDirectory = "conversations"
        /// Subdirectory inside Application Support for downloaded model files.
        static let modelsDirectory = "models"
    }

    // MARK: - Inference

    enum Inference {
        /// Hard cap on context window tokens across all models.
        static let maxContextTokens = 4096
        /// Tokens reserved for the next response; trigger trimming below this headroom.
        static let contextHeadroomTokens = 256
        /// Available RAM threshold (bytes) below which the model is proactively unloaded.
        static let memoryPressureThresholdBytes: Int64 = 500 * 1024 * 1024 // 500 MB
        /// Default maximum tokens generated per response.
        static let defaultMaxTokens = 512
        /// Lower temperature reduces hallucinations at the cost of creativity.
        static let defaultTemperature: Float = 0.3
        /// Default top-p nucleus sampling threshold.
        static let defaultTopP: Float = 0.9
    }

    // MARK: - RAG

    enum RAG {
        /// Maximum number of chunks retrieved per query.
        static let topK = 1
        /// Minimum cosine similarity for a chunk to be considered relevant.
        /// Apple's NLEmbedding L2-normalised dot-product scores range roughly 0–1.
        static let similarityThreshold: Float = 0.35
        /// Token budget reserved for the injected RAG context block per turn.
        /// Keep this plus the system prompt under ~70 tokens so user messages fit.
        static let contextTokenBudget = 60
        /// Prefix injected before the retrieved passage in the prompt.
        static let contextPrefix = "Reference:\n"
    }

    // MARK: - UI

    enum UI {
        /// Maximum characters the user can enter in a single message.
        static let maxUserMessageLength = 4000
        /// Memory monitor polling interval while inference is active (seconds).
        static let memoryPollIntervalSeconds: TimeInterval = 5
    }

    // MARK: - Model download

    enum ModelDownload {
        /// Base URL for the model manifest and download CDN.
        static let manifestBaseURL = "https://models.pocketmind.app"
        static let manifestFilename = "model_manifest.json"
    }
}
