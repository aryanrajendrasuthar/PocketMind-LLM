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

import CoreML
import Foundation
import os.log

/// Manages CoreML model lifecycle and drives autoregressive token generation.
///
/// The model is loaded lazily on the first `generate()` call and may be unloaded
/// by `MemoryManager` under memory pressure. It reloads automatically on the next call.
///
/// All inference runs on a background priority task — this actor never blocks the main thread.
actor InferenceEngine {

    // MARK: - Types

    enum InferenceError: Error, LocalizedError {
        case modelNotFound(URL)
        case modelLoadFailed(String)
        case tokenizerNotReady
        case invalidModelOutput
        case contextExceeded

        var errorDescription: String? {
            switch self {
            case .modelNotFound(let url):   return "Model not found at \(url.lastPathComponent)."
            case .modelLoadFailed(let msg): return "Model load failed: \(msg)"
            case .tokenizerNotReady:        return "Tokenizer is not initialized."
            case .invalidModelOutput:       return "Model produced unexpected output shape."
            case .contextExceeded:          return "Input exceeds model context window."
            }
        }
    }

    // MARK: - State

    private var model: MLModel?
    private let modelURL: URL
    private let tokenizer: Tokenizer
    private let contextLength: Int
    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "InferenceEngine")

    // MARK: - Init

    /// - Parameters:
    ///   - modelURL: Path to the `.mlpackage` directory.
    ///   - tokenizer: Fully initialized `Tokenizer` instance.
    ///   - contextLength: Maximum token sequence length the model accepts.
    init(modelURL: URL, tokenizer: Tokenizer, contextLength: Int = Constants.Inference.maxContextTokens) {
        self.modelURL = modelURL
        self.tokenizer = tokenizer
        self.contextLength = contextLength
    }

    // MARK: - Public API

    /// Stream tokens for the given prompt. The returned `AsyncStream` emits
    /// `InferenceToken` values until EOS, `maxTokens` is reached, or the task is cancelled.
    ///
    /// The final element always has `isFinished == true`.
    func generate(
        prompt: String,
        maxTokens: Int = Constants.Inference.defaultMaxTokens,
        temperature: Float = Constants.Inference.defaultTemperature,
        topP: Float = Constants.Inference.defaultTopP
    ) -> AsyncStream<InferenceToken> {
        AsyncStream { continuation in
            Task(priority: .userInitiated) {
                do {
                    if !self.isLoaded() {
                        try await self.loadModel()
                    }
                    await self.runGeneration(
                        prompt: prompt,
                        maxTokens: maxTokens,
                        temperature: temperature,
                        topP: topP,
                        continuation: continuation
                    )
                } catch {
                    self.logger.error("Generation error: \(error.localizedDescription, privacy: .public)")
                    continuation.finish()
                }
            }
        }
    }

    /// Load the CoreML model from `modelURL` on a background task.
    /// Must not be called from the main thread.
    func loadModel() async throws {
        guard !isLoaded() else { return }
        logger.info("Loading model from: \(self.modelURL.lastPathComponent, privacy: .public)")

        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw InferenceError.modelNotFound(modelURL)
        }

        let config = MLModelConfiguration()
        config.computeUnits = .all

        let loaded: MLModel
        do {
            loaded = try await MLModel.load(contentsOf: modelURL, configuration: config)
        } catch {
            throw InferenceError.modelLoadFailed(error.localizedDescription)
        }

        model = loaded
        logger.info("Model loaded successfully.")
    }

    /// Release the `MLModel` from memory. CoreML frees GPU/ANE buffers when the object is released.
    func unloadModel() {
        guard model != nil else { return }
        model = nil
        logger.info("Model unloaded.")
    }

    /// Returns `true` if the model is currently resident in memory.
    func isLoaded() -> Bool {
        model != nil
    }

    // MARK: - Autoregressive generation

    private func runGeneration(
        prompt: String,
        maxTokens: Int,
        temperature: Float,
        topP: Float,
        continuation: AsyncStream<InferenceToken>.Continuation
    ) async {
        guard let model else {
            continuation.finish()
            return
        }

        let inputIds = tokenizer.encode(prompt)
        var context = inputIds

        let startTime = Date()
        var firstTokenTime: TimeInterval?
        var tokensGenerated = 0

        for step in 0..<maxTokens {
            guard !Task.isCancelled else {
                continuation.finish()
                return
            }

            // Truncate context to fit within model window, keeping as many recent tokens as possible
            let window = Array(context.suffix(contextLength))

            do {
                let logits = try predict(model: model, inputIds: window)
                let nextId = sample(logits: logits, temperature: temperature, topP: topP)

                if step == 0 {
                    firstTokenTime = Date().timeIntervalSince(startTime)
                }

                let text = tokenizer.decodeSingle(nextId)
                let token = InferenceToken(text: text, tokenId: nextId, isFinished: false)
                continuation.yield(token)
                tokensGenerated += 1
                context.append(nextId)

                if nextId == tokenizer.eosTokenId {
                    break
                }
            } catch {
                logger.error("Predict step \(step) failed: \(error.localizedDescription, privacy: .public)")
                break
            }
        }

        continuation.yield(.finished())
        continuation.finish()

        let totalTime = Date().timeIntervalSince(startTime)
        logger.info(
            "Generation complete — \(tokensGenerated) tokens in \(String(format: "%.2f", totalTime))s " +
            "(\(String(format: "%.1f", Double(tokensGenerated) / totalTime)) tok/s)"
        )
    }

    // MARK: - CoreML prediction

    /// Run a single forward pass and return the logits for the last token position.
    private func predict(model: MLModel, inputIds: [Int]) throws -> [Float] {
        let seqLen = inputIds.count
        guard seqLen > 0, seqLen <= contextLength else {
            throw InferenceError.contextExceeded
        }

        // Build input_ids MLMultiArray — shape [1, contextLength], padded
        let inputArray = try MLMultiArray(shape: [1, contextLength as NSNumber], dataType: .int32)
        let maskArray  = try MLMultiArray(shape: [1, contextLength as NSNumber], dataType: .int32)

        for i in 0..<contextLength {
            inputArray[i] = 0
            maskArray[i]  = 0
        }
        for (i, id) in inputIds.enumerated() {
            inputArray[i] = NSNumber(value: id)
            maskArray[i]  = 1
        }

        let inputFeatures = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids":      MLFeatureValue(multiArray: inputArray),
            "attention_mask": MLFeatureValue(multiArray: maskArray),
        ])

        let output = try model.prediction(from: inputFeatures)

        // Extract logits at the last valid token position
        guard let logitsFeature = output.featureValue(for: "logits_out") ?? output.featureValue(for: "logits"),
              let logitsArray = logitsFeature.multiArrayValue else {
            throw InferenceError.invalidModelOutput
        }

        // logitsArray shape: [1, seqLen, vocabSize]
        let vocabSize = logitsArray.shape.last.map { Int(truncating: $0) } ?? 0
        guard vocabSize > 0 else { throw InferenceError.invalidModelOutput }

        // Offset to the last non-padding position
        let offset = (seqLen - 1) * vocabSize
        return (0..<vocabSize).map { Float(truncating: logitsArray[offset + $0]) }
    }

    // MARK: - Sampling

    /// Sample the next token using temperature scaling + top-p nucleus sampling.
    private func sample(logits: [Float], temperature: Float, topP: Float) -> Int {
        guard !logits.isEmpty else { return tokenizer.eosTokenId }

        // Greedy decode at temperature 0
        if temperature <= 1e-6 {
            return logits.indices.max(by: { logits[$0] < logits[$1] }) ?? tokenizer.eosTokenId
        }

        // Temperature scaling
        let scaled = logits.map { $0 / temperature }

        // Softmax — subtract max for numerical stability
        let maxVal = scaled.max() ?? 0
        var probs = scaled.map { exp($0 - maxVal) }
        let sum = probs.reduce(0, +)
        probs = probs.map { $0 / sum }

        // Top-p nucleus filtering: sort by probability descending, keep until cumulative > topP
        let sorted = probs.enumerated().sorted { $0.element > $1.element }
        var cumulative: Float = 0
        var nucleus: [(offset: Int, element: Float)] = []
        for entry in sorted {
            nucleus.append(entry)
            cumulative += entry.element
            if cumulative >= topP { break }
        }

        // Re-normalize nucleus
        let nucleusSum = nucleus.map(\.element).reduce(0, +)
        let normalized = nucleus.map { ($0.offset, $0.element / nucleusSum) }

        // Weighted random draw
        let rand = Float.random(in: 0..<1)
        var acc: Float = 0
        for (idx, prob) in normalized {
            acc += prob
            if rand < acc { return idx }
        }
        return normalized.last?.0 ?? tokenizer.eosTokenId
    }
}
