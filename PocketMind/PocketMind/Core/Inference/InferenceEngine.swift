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

import Accelerate
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
    private var inputBuffer: MLMultiArray?  // reused every predict step — avoids per-step allocation
    private var isModelLoading = false      // guards against concurrent loadModel() calls
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
                        // If a background preload is in progress, wait for it instead of
                        // racing: the old guard in loadModel() returns early for concurrent
                        // callers, which left this Task with a nil model and 0 tokens generated.
                        while self.isModelLoading {
                            await Task.yield()
                        }
                        // Re-check after the background load finished (it may have failed).
                        if !self.isLoaded() {
                            try await self.loadModel()
                        }
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
        // isModelLoading is set before the first await, so it is visible to any
        // second caller that arrives while this method is suspended at MLModel.load().
        // Without this guard, two concurrent callers both pass !isLoaded() and race.
        guard !isLoaded(), !isModelLoading else { return }
        isModelLoading = true
        defer { isModelLoading = false }
        logger.info("Loading model from: \(self.modelURL.lastPathComponent, privacy: .public)")

        let urlToLoad: URL
        if FileManager.default.fileExists(atPath: modelURL.path) {
            // Production path: model downloaded to Application Support.
            urlToLoad = modelURL
        } else {
            let baseName = modelURL.lastPathComponent
                .replacingOccurrences(of: "-coreml", with: "")

            // Compiled model cached in Application Support from a previous first-launch compile.
            let compiledCacheURL = modelURL.deletingLastPathComponent()
                .appendingPathComponent("\(baseName).mlmodelc")

            if FileManager.default.fileExists(atPath: compiledCacheURL.path) {
                urlToLoad = compiledCacheURL
                logger.info("Loading compiled model from cache.")
            } else if let precompiled = Bundle.main.url(forResource: baseName, withExtension: "mlmodelc") {
                // Xcode pre-compiled the model during build (legacy path).
                urlToLoad = precompiled
                logger.info("Loading pre-compiled bundle model.")
            } else if let rawPackage = Bundle.main.url(forResource: baseName, withExtension: "mlpackage") {
                // Raw mlpackage bundled without Xcode compilation. Compile once and cache.
                // MLModel.load() does not accept raw mlpackage; compileModel() is required.
                logger.info("First launch: compiling bundled mlpackage — this takes ~60s and is cached.")
                let tempURL = try await MLModel.compileModel(at: rawPackage)
                let cacheDir = compiledCacheURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: compiledCacheURL.path) {
                    try FileManager.default.removeItem(at: compiledCacheURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: compiledCacheURL)
                urlToLoad = compiledCacheURL
                logger.info("Model compiled and cached at: \(compiledCacheURL.lastPathComponent, privacy: .public)")
            } else {
                throw InferenceError.modelNotFound(modelURL)
            }
        }

        let config = MLModelConfiguration()
        // ANE is a dedicated chip not shared with the GPU renderer; avoids
        // kIOGPUCommandBufferCallbackErrorInnocentVictim when the system UI
        // causes a GPU reset while our Metal command buffers are queued.
        config.computeUnits = .cpuAndNeuralEngine

        let loaded: MLModel
        do {
            loaded = try await MLModel.load(contentsOf: urlToLoad, configuration: config)
        } catch {
            throw InferenceError.modelLoadFailed(error.localizedDescription)
        }

        model = loaded
        inputBuffer = try MLMultiArray(shape: [1, contextLength as NSNumber], dataType: .int32)
        logger.info("Model loaded successfully.")
    }

    /// Release the `MLModel` from memory. CoreML frees GPU/ANE buffers when the object is released.
    func unloadModel() {
        guard model != nil else { return }
        model = nil
        inputBuffer = nil
        isModelLoading = false
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
        var tokensGenerated = 0

        for _ in 0..<maxTokens {
            guard !Task.isCancelled else {
                continuation.finish()
                return
            }
            // Yield between tokens so the cooperative thread pool can handle UI work.
            await Task.yield()

            // Truncate context to fit within model window, keeping as many recent tokens as possible
            let window = Array(context.suffix(contextLength))

            do {
                let logits = try predict(model: model, inputIds: window)
                let nextId = sample(logits: logits, temperature: temperature, topP: topP)

                let text = tokenizer.decodeSingle(nextId)
                let token = InferenceToken(text: text, tokenId: nextId, isFinished: false)
                continuation.yield(token)
                tokensGenerated += 1
                context.append(nextId)

                if tokenizer.isStopToken(nextId) {
                    break
                }
            } catch {
                logger.error("Predict step failed: \(error.localizedDescription, privacy: .public)")
                break
            }
        }

        continuation.yield(.finished())
        continuation.finish()

        let totalTime = Date().timeIntervalSince(startTime)
        let tps = totalTime > 0 ? Double(tokensGenerated) / totalTime : 0
        logger.info("Generation complete — \(tokensGenerated, privacy: .public) tokens in \(String(format: "%.2f", totalTime), privacy: .public)s (\(String(format: "%.1f", tps), privacy: .public) tok/s)")
    }

    // MARK: - CoreML prediction

    /// Run a single forward pass and return the logits for the last token position.
    private func predict(model: MLModel, inputIds: [Int]) throws -> [Float] {
        // Bail out before an expensive 5-second CoreML call if the task was cancelled.
        try Task.checkCancellation()
        let seqLen = inputIds.count
        guard seqLen > 0, seqLen <= contextLength else {
            throw InferenceError.contextExceeded
        }

        // Reuse the pre-allocated buffer — avoids a 1 KB heap allocation every token step.
        // The CoreML model bakes causal masking internally; no attention_mask input needed.
        guard let inputArray = inputBuffer else { throw InferenceError.modelLoadFailed("input buffer nil") }
        // Use dataPointer (plain UnsafeMutableRawPointer) instead of withUnsafeMutableBytes
        // whose closure signature changed across iOS SDK versions.
        let int32Ptr = inputArray.dataPointer.assumingMemoryBound(to: Int32.self)
        for i in 0..<contextLength { int32Ptr[i] = 0 }
        for (i, id) in inputIds.enumerated() { int32Ptr[i] = Int32(id) }

        let inputFeatures = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputArray),
        ])

        let output = try model.prediction(from: inputFeatures)

        // Extract logits at the last valid token position
        guard let outputName = output.featureNames.first,
              let logitsFeature = output.featureValue(for: outputName),
              let logitsArray = logitsFeature.multiArrayValue else {
            throw InferenceError.invalidModelOutput
        }

        // logitsArray shape: [1, contextLength, vocabSize]
        let vocabSize = logitsArray.shape.last.map { Int(truncating: $0) } ?? 0
        guard vocabSize > 0 else { throw InferenceError.invalidModelOutput }

        // Use raw pointer bulk-read instead of per-element NSNumber subscript (128k calls = minutes).
        let offset = (seqLen - 1) * vocabSize
        var result = [Float](repeating: 0, count: vocabSize)
        switch logitsArray.dataType {
        case .float16:
            logitsArray.withUnsafeBytes { ptr in
                let f16 = ptr.bindMemory(to: Float16.self)
                for i in 0..<vocabSize { result[i] = Float(f16[offset + i]) }
            }
        default:
            logitsArray.withUnsafeBytes { ptr in
                let f32 = ptr.bindMemory(to: Float.self)
                for i in 0..<vocabSize { result[i] = f32[offset + i] }
            }
        }
        return result
    }

    // MARK: - Sampling

    /// Sample the next token using temperature scaling + top-p nucleus sampling.
    ///
    /// Uses Accelerate (vDSP/vForce SIMD) for the softmax and a partial sort over
    /// only the high-probability candidates instead of sorting all 128k logits.
    /// At temperature 0.3 this reduces the sort from 128k → ~30 elements.
    private func sample(logits: [Float], temperature: Float, topP: Float) -> Int {
        guard !logits.isEmpty else { return tokenizer.eosTokenId }
        let n = logits.count

        // Greedy decode — vDSP_maxvi is a single SIMD pass over 128k floats
        if temperature <= 1e-6 {
            var maxVal: Float = 0
            var maxIdx: vDSP_Length = 0
            vDSP_maxvi(logits, 1, &maxVal, &maxIdx, vDSP_Length(n))
            return Int(maxIdx)
        }

        // 1. Temperature scaling: scaled = logits / temperature
        var invT: Float = 1.0 / temperature
        var scaled = [Float](repeating: 0, count: n)
        vDSP_vsmul(logits, 1, &invT, &scaled, 1, vDSP_Length(n))

        // 2. Subtract max for numerical stability
        var maxS: Float = 0
        vDSP_maxv(scaled, 1, &maxS, vDSP_Length(n))
        var negMax = -maxS
        var shifted = [Float](repeating: 0, count: n)
        vDSP_vsadd(scaled, 1, &negMax, &shifted, 1, vDSP_Length(n))

        // 3. exp() via vForce (SIMD, ~10× faster than element-wise Swift)
        var probs = [Float](repeating: 0, count: n)
        var nI = Int32(n)
        vvexpf(&probs, shifted, &nI)

        // 4. Normalize
        var sum: Float = 0
        vDSP_sve(probs, 1, &sum, vDSP_Length(n))
        var invSum: Float = 1.0 / sum
        var normalized = [Float](repeating: 0, count: n)
        vDSP_vsmul(probs, 1, &invSum, &normalized, 1, vDSP_Length(n))

        // 5. Partial sort: collect only candidates above 0.1% of the max probability.
        //    For temperature ≤ 1.0 this is typically < 100 tokens, reducing the
        //    sort from O(128k·log128k) to O(100·log100) — ~2000× fewer comparisons.
        var probMax: Float = 0
        vDSP_maxv(normalized, 1, &probMax, vDSP_Length(n))
        let minProb = probMax * 0.001

        var nucleus: [(idx: Int, prob: Float)] = []
        nucleus.reserveCapacity(64)
        for i in 0..<n where normalized[i] >= minProb {
            nucleus.append((i, normalized[i]))
        }
        nucleus.sort { $0.prob > $1.prob }

        // 6. Top-p cutoff
        var cumulative: Float = 0
        var cutIdx = nucleus.count
        for (j, e) in nucleus.enumerated() {
            cumulative += e.prob
            if cumulative >= topP { cutIdx = j + 1; break }
        }
        let candidates = nucleus.prefix(cutIdx)
        guard !candidates.isEmpty else { return tokenizer.eosTokenId }

        // 7. Weighted random draw from nucleus
        let candSum = candidates.reduce(0.0 as Float) { $0 + $1.prob }
        guard candSum > 0 else { return candidates[candidates.startIndex].idx }
        let rand = Float.random(in: 0..<candSum)
        var acc: Float = 0
        for (idx, prob) in candidates {
            acc += prob
            if rand < acc { return idx }
        }
        return candidates.last?.idx ?? tokenizer.eosTokenId
    }
}
