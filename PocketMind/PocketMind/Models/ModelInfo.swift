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
        // ── Llama 3.2 1B ─────────────────────────────────────────────────────────
        // Fast (~1 tok/s on A14+). Context exported at 256 tokens; RAG compensates
        // for the small window by injecting the most relevant document passage.
        ModelInfo(
            id: "pocketmind_llama32_1b-coreml",
            displayName: "Llama 3.2 1B",
            version: "1.0.0",
            quantization: "iOS 18 compressed",
            fileSizeBytes: 696_254_464,
            sha256: "",
            minIOS: "18.0",
            minRAMGB: 3,
            minDevice: "iPhone 12",
            minChip: "A14",
            recommendedDevices: ["iPhone 12", "iPhone 13", "iPhone 14", "iPhone 15"],
            contextLength: 256,
            maxTokens: 150,     // reduced from 200 so the RAG passage + system prompt fit
            knowledgeCutoff: "2024-04",
            capabilities: ["reasoning", "writing", "code", "summarization"],
            offlineLimitations: ["no_live_data", "no_web_search", "no_real_time_events"]
        ),

        // ── Llama 3.2 3B ─────────────────────────────────────────────────────────
        // ~2-3× better quality, ~2-3× slower (~0.4 tok/s on A17 Pro).
        // Convert with: python ModelTooling/scripts/convert_to_coreml.py
        //   using model_id = "meta-llama/Llama-3.2-3B-Instruct" (free on HuggingFace).
        // Export with sequence_length = 512 for a usable context at acceptable speed.
        ModelInfo(
            id: "pocketmind_llama32_3b-coreml",
            displayName: "Llama 3.2 3B",
            version: "1.0.0",
            quantization: "iOS 18 compressed",
            fileSizeBytes: 1_932_735_283,
            sha256: "",
            minIOS: "18.0",
            minRAMGB: 4,
            minDevice: "iPhone 14",
            minChip: "A15",
            recommendedDevices: ["iPhone 14", "iPhone 15", "iPhone 15 Pro", "iPhone 16"],
            contextLength: 512,
            maxTokens: 200,
            knowledgeCutoff: "2024-04",
            capabilities: ["reasoning", "writing", "code", "summarization", "analysis"],
            offlineLimitations: ["no_live_data", "no_web_search", "no_real_time_events"]
        ),

        // ── Phi-3 Mini 3.8B ──────────────────────────────────────────────────────
        // Best reasoning of the three; designed for constrained deployment.
        // Free from HuggingFace: "microsoft/Phi-3-mini-4k-instruct".
        // Uses a different chat template — update buildPrompt() before activating.
        ModelInfo(
            id: "pocketmind_phi3_mini-coreml",
            displayName: "Phi-3 Mini 3.8B",
            version: "1.0.0",
            quantization: "iOS 18 compressed",
            fileSizeBytes: 2_469_606_195,
            sha256: "",
            minIOS: "18.0",
            minRAMGB: 6,
            minDevice: "iPhone 15 Pro",
            minChip: "A17",
            recommendedDevices: ["iPhone 15 Pro", "iPhone 15 Pro Max", "iPhone 16 Pro"],
            contextLength: 512,
            maxTokens: 200,
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
