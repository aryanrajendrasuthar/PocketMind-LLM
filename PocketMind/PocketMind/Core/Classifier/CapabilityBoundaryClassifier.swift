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
import NaturalLanguage
import os.log

/// Classifies user queries as offline-capable or requiring live data.
///
/// Two-stage pipeline:
///
/// **Stage 1 — Rule-based (always runs, < 1ms)**
/// Deterministic keyword matching against `ClassifierRules`. Fast enough to run
/// synchronously on the calling thread with no perceptible latency.
///
/// **Stage 2 — CoreML NLModel (runs only when Stage 1 returns `.fullyOffline`)**
/// A lightweight (< 5 MB) binary text classifier trained on ~10,000 labeled examples.
/// Falls back gracefully if the model file is absent — Stage 1 result stands.
struct CapabilityBoundaryClassifier {

    // MARK: - Configuration

    /// Confidence threshold: Stage 2 must exceed this to override Stage 1's `.fullyOffline`.
    private static let mlConfidenceThreshold: Double = 0.75

    // MARK: - State

    private let nlModel: NLModel?
    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "Classifier")

    // MARK: - Init

    /// Load the CoreML classifier from the app bundle if present.
    /// Initialization never throws — a missing model silently disables Stage 2.
    init() {
        if let url = Bundle.main.url(forResource: "CapabilityClassifier", withExtension: "mlmodelc") {
            nlModel = try? NLModel(contentsOf: url)
            if nlModel != nil {
                Logger(subsystem: Constants.bundleIdentifier, category: "Classifier")
                    .info("CoreML classifier loaded.")
            }
        } else {
            nlModel = nil
        }
    }

    /// Package-internal init that accepts a pre-loaded NLModel — used in tests.
    init(nlModel: NLModel?) {
        self.nlModel = nlModel
    }

    // MARK: - Public API

    /// Classify a user query. Always returns synchronously.
    func classify(_ query: String) -> QueryCapability {
        let normalized = normalize(query)

        guard !normalized.isEmpty else {
            return .fullyOffline
        }

        // Stage 1: rule-based
        if let ruleResult = applyRules(normalized) {
            logger.debug("Stage 1 matched: \(query.prefix(60), privacy: .public)")
            return ruleResult
        }

        // Stage 2: CoreML NLModel
        if let mlResult = applyMLModel(normalized) {
            logger.debug("Stage 2 classified: \(query.prefix(60), privacy: .public)")
            return mlResult
        }

        return .fullyOffline
    }

    // MARK: - Stage 1: Rule-based

    private func applyRules(_ normalized: String) -> QueryCapability? {
        // Check explicit standalone multi-word phrases first — highest confidence
        for phrase in ClassifierRules.explicitLivePhrases where normalized.contains(phrase) {
            if let category = matchingCategory(for: normalized) {
                return .requiresLiveData(reason: category.reason, suggestion: category.suggestion)
            }
            // Phrase matched but no specific category — use generic fallback
            return .requiresLiveData(
                reason: "This question needs live information that PocketMind doesn't have access to.",
                suggestion: "Try Safari or Siri for up-to-date information."
            )
        }

        // Check if an offline-safe modifier is present — if so, skip temporal+noun matching
        let hasOfflineSafeModifier = ClassifierRules.offlineSafeModifiers.contains { mod in
            normalized.hasPrefix(mod) || normalized.contains(" \(mod) ")
        }
        if hasOfflineSafeModifier {
            return nil
        }

        // Temporal trigger × domain noun matching
        let hasTemporal = ClassifierRules.temporalTriggers.contains { trigger in
            containsWord(normalized, word: trigger)
        }
        guard hasTemporal else { return nil }

        // Find which category's domain nouns appear in the query
        return matchingCategory(for: normalized).map { category in
            .requiresLiveData(reason: category.reason, suggestion: category.suggestion)
        }
    }

    private func matchingCategory(for normalized: String) -> ClassifierRules.CategoryRule? {
        for category in ClassifierRules.categories {
            let domainMatch = category.domainNouns.contains { containsWord(normalized, word: $0) }
            let standaloneMatch = category.standaloneNouns.contains { normalized.contains($0) }
            if domainMatch || standaloneMatch {
                return category
            }
        }
        return nil
    }

    // MARK: - Stage 2: CoreML NLModel

    private func applyMLModel(_ normalized: String) -> QueryCapability? {
        guard let model = nlModel else { return nil }

        guard let prediction = model.predictedLabel(for: normalized),
              prediction == "requires_live_data" else { return nil }

        // Check confidence meets threshold
        let probs = model.predictedLabelHypotheses(for: normalized, maximumCount: 2)
        guard let confidence = probs[prediction], confidence >= Self.mlConfidenceThreshold else {
            return nil
        }

        return .requiresLiveData(
            reason: "This question likely needs live information that PocketMind doesn't have.",
            suggestion: "Try Safari or Siri for the most up-to-date answer."
        )
    }

    // MARK: - String utilities

    /// Lowercase, strip punctuation, normalize whitespace.
    private func normalize(_ query: String) -> String {
        var text = query.lowercased()
        // Strip control characters (security: prevent prompt injection via hidden chars)
        text = text.unicodeScalars
            .filter { scalar in
                let value = scalar.value
                return value >= 0x20 || value == 0x0A || value == 0x09
            }
            .map(String.init)
            .joined()

        // Collapse multiple spaces
        let components = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return components.joined(separator: " ")
    }

    /// Word-boundary aware containment check. Avoids "trade" matching "trademark".
    private func containsWord(_ text: String, word: String) -> Bool {
        // Multi-word phrases: simple substring match is fine
        if word.contains(" ") { return text.contains(word) }

        // Single word: require word boundaries
        guard let range = text.range(of: word) else { return false }
        let atStart = range.lowerBound == text.startIndex
        let atEnd   = range.upperBound == text.endIndex

        let charBefore = atStart ? nil : text[text.index(before: range.lowerBound)]
        let charAfter  = atEnd   ? nil : text[range.upperBound]

        let boundaryBefore = atStart || !(charBefore?.isLetter == true || charBefore?.isNumber == true)
        let boundaryAfter  = atEnd   || !(charAfter?.isLetter  == true || charAfter?.isNumber  == true)

        return boundaryBefore && boundaryAfter
    }
}
