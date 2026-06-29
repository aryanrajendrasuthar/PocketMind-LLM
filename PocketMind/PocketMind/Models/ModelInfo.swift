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

/// Describes a supported on-device model.
struct ModelInfo: Identifiable, Codable, Sendable, Hashable {
    let id: String                  // e.g. "pocketmind_llama32_1b-coreml"
    let displayName: String
    let version: String
    let quantization: String        // e.g. "INT4 Q4_K_M"
    let fileSizeBytes: Int64
    let sha256: String
    let minIOS: String
    let minRAMGB: Int
    let minDevice: String
    let minChip: String
    let recommendedDevices: [String]
    let contextLength: Int
    let maxTokens: Int
    let knowledgeCutoff: String
    let capabilities: [String]
    let offlineLimitations: [String]

    var fileSizeMB: Double { Double(fileSizeBytes) / (1024 * 1024) }
    var fileSizeGB: Double { Double(fileSizeBytes) / (1024 * 1024 * 1024) }

    /// True if the device meets the minimum RAM requirement.
    func isCompatible(withAvailableRAMGB ram: Int) -> Bool {
        ram >= minRAMGB
    }
}

extension ModelInfo {

    /// All models supported by PocketMind, in ascending capability order.
    static let allModels: [ModelInfo] = [
        ModelInfo(
            id: "pocketmind_llama32_1b-coreml",
            displayName: "Llama 3.2 1B",
            version: "1.0.0",
            quantization: "INT4 Q4_K_M",
            fileSizeBytes: 644_245_094,
            sha256: "",         // populated from manifest at download time
            minIOS: "17.0",
            minRAMGB: 3,
            minDevice: "iPhone 12",
            minChip: "A14",
            recommendedDevices: ["iPhone 12", "iPhone 13", "iPhone 14"],
            contextLength: 4096,
            maxTokens: 512,
            knowledgeCutoff: "2024-04",
            capabilities: ["reasoning", "writing", "code", "summarization"],
            offlineLimitations: ["no_live_data", "no_web_search", "no_real_time_events"]
        ),
        ModelInfo(
            id: "pocketmind_llama32_3b-coreml",
            displayName: "Llama 3.2 3B",
            version: "1.0.0",
            quantization: "INT4 Q4_K_M",
            fileSizeBytes: 1_932_735_283,
            sha256: "",
            minIOS: "17.0",
            minRAMGB: 4,
            minDevice: "iPhone 14",
            minChip: "A15",
            recommendedDevices: ["iPhone 14", "iPhone 15"],
            contextLength: 4096,
            maxTokens: 512,
            knowledgeCutoff: "2024-04",
            capabilities: ["reasoning", "writing", "code", "summarization"],
            offlineLimitations: ["no_live_data", "no_web_search", "no_real_time_events"]
        ),
        ModelInfo(
            id: "pocketmind_phi3_mini-coreml",
            displayName: "Phi-3 Mini 3.8B",
            version: "1.0.0",
            quantization: "INT4 Q4_K_M",
            fileSizeBytes: 2_469_606_195,
            sha256: "",
            minIOS: "17.0",
            minRAMGB: 6,
            minDevice: "iPhone 15 Pro",
            minChip: "A17",
            recommendedDevices: ["iPhone 15 Pro", "iPhone 15 Pro Max", "iPhone 16 Pro"],
            contextLength: 4096,
            maxTokens: 512,
            knowledgeCutoff: "2024-04",
            capabilities: ["reasoning", "writing", "code", "summarization", "math"],
            offlineLimitations: ["no_live_data", "no_web_search", "no_real_time_events"]
        ),
    ]

    /// Recommend the best model for the given available RAM.
    static func recommended(forAvailableRAMGB ram: Int) -> ModelInfo {
        allModels.filter { $0.isCompatible(withAvailableRAMGB: ram) }.last ?? allModels[0]
    }
}
