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
        /// Default sampling temperature.
        static let defaultTemperature: Float = 0.7
        /// Default top-p nucleus sampling threshold.
        static let defaultTopP: Float = 0.9
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
