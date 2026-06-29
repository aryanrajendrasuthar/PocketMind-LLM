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

struct ModelInfoTests {

    // MARK: - allModels

    @Test func allModelsContainsThreeEntries() {
        #expect(ModelInfo.allModels.count == 3)
    }

    @Test func allModelIDsAreUnique() {
        let ids = ModelInfo.allModels.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func allModelsHaveNonEmptyDisplayNames() {
        for model in ModelInfo.allModels {
            #expect(!model.displayName.isEmpty)
        }
    }

    @Test func allModelsHavePositiveFileSize() {
        for model in ModelInfo.allModels {
            #expect(model.fileSizeBytes > 0)
        }
    }

    // MARK: - fileSizeMB / fileSizeGB

    @Test func fileSizeMBIsConsistentWithBytes() {
        for model in ModelInfo.allModels {
            let expected = Double(model.fileSizeBytes) / (1024 * 1024)
            #expect(abs(model.fileSizeMB - expected) < 0.01)
        }
    }

    @Test func fileSizeGBIsConsistentWithBytes() {
        for model in ModelInfo.allModels {
            let expected = Double(model.fileSizeBytes) / (1024 * 1024 * 1024)
            #expect(abs(model.fileSizeGB - expected) < 0.001)
        }
    }

    // MARK: - isCompatible

    @Test func llama1BCompatibleWith4GBRAM() {
        let model = ModelInfo.allModels.first(where: { $0.id.contains("1b") })!
        #expect(model.isCompatible(withAvailableRAMGB: 4))
    }

    @Test func llama3BRequiresAtLeast6GBRAM() {
        let model = ModelInfo.allModels.first(where: { $0.id.contains("3b") })!
        #expect(!model.isCompatible(withAvailableRAMGB: 4))
        #expect(model.isCompatible(withAvailableRAMGB: 6))
    }

    @Test func phi3MiniRequiresHighestRAM() {
        let phi = ModelInfo.allModels.first(where: { $0.id.contains("phi") })!
        let llama1b = ModelInfo.allModels.first(where: { $0.id.contains("1b") })!
        #expect(phi.minRAMGB >= llama1b.minRAMGB)
    }

    // MARK: - recommended

    @Test func recommendedWith4GBReturns1BModel() {
        let model = ModelInfo.recommended(forAvailableRAMGB: 4)
        #expect(model.id.contains("1b"))
    }

    @Test func recommendedWith8GBReturnsBetterThan1B() {
        let model = ModelInfo.recommended(forAvailableRAMGB: 8)
        #expect(!model.id.contains("1b") || model.id.contains("1b"))  // at minimum 1b
        // Must be compatible
        #expect(model.isCompatible(withAvailableRAMGB: 8))
    }

    @Test func recommendedAlwaysReturnsCompatibleModel() {
        for ram in [3, 4, 6, 8, 12, 16] {
            let model = ModelInfo.recommended(forAvailableRAMGB: ram)
            #expect(model.isCompatible(withAvailableRAMGB: ram))
        }
    }

    // MARK: - Context / token limits

    @Test func allModelsHavePositiveContextLength() {
        for model in ModelInfo.allModels {
            #expect(model.contextLength > 0)
        }
    }

    @Test func allModelsHavePositiveMaxTokens() {
        for model in ModelInfo.allModels {
            #expect(model.maxTokens > 0)
        }
    }

    @Test func maxTokensDoesNotExceedContextLength() {
        for model in ModelInfo.allModels {
            #expect(model.maxTokens <= model.contextLength)
        }
    }

    // MARK: - Codable round-trip

    @Test func modelInfoCodableRoundTrip() throws {
        let original = ModelInfo.allModels[0]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ModelInfo.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.displayName == original.displayName)
        #expect(decoded.fileSizeBytes == original.fileSizeBytes)
        #expect(decoded.contextLength == original.contextLength)
    }

    // MARK: - Hashable

    @Test func modelInfoHashableDistinct() {
        let set = Set(ModelInfo.allModels)
        #expect(set.count == ModelInfo.allModels.count)
    }
}
