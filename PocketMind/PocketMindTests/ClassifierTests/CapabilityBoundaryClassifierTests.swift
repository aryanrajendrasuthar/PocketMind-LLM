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

import XCTest
@testable import PocketMind

/// Tests for `CapabilityBoundaryClassifier` — 30 sample queries must achieve ≥ 25 correct.
///
/// Tests run Stage 1 only (no CoreML model required in CI). The classifier is
/// initialized with `nlModel: nil` to isolate the rule-based pipeline.
final class CapabilityBoundaryClassifierTests: XCTestCase {

    private let classifier = CapabilityBoundaryClassifier(nlModel: nil)

    // MARK: - Labeled test suite (30 queries)

    private struct TestCase {
        let query: String
        let expectedOffline: Bool
        let description: String
    }

    private let testCases: [TestCase] = [
        // ── Live data queries (expect isOfflineCapable == false) ──────────────
        TestCase(query: "What is the stock price of Apple today?",
                 expectedOffline: false, description: "Stock price today"),
        TestCase(query: "What is Bitcoin worth right now?",
                 expectedOffline: false, description: "Crypto price now"),
        TestCase(query: "What is the weather like today?",
                 expectedOffline: false, description: "Weather today"),
        TestCase(query: "Will it rain tomorrow?",
                 expectedOffline: false, description: "Rain forecast"),
        TestCase(query: "What happened in the news today?",
                 expectedOffline: false, description: "News today"),
        TestCase(query: "What are the latest sports scores?",
                 expectedOffline: false, description: "Latest scores"),
        TestCase(query: "Who won the game last night?",
                 expectedOffline: false, description: "Game result last night"),
        TestCase(query: "What is the current interest rate?",
                 expectedOffline: false, description: "Current interest rate"),
        TestCase(query: "What time does Target close today?",
                 expectedOffline: false, description: "Store hours today"),
        TestCase(query: "Is McDonald's open right now?",
                 expectedOffline: false, description: "Business open now"),
        TestCase(query: "What is the latest news?",
                 expectedOffline: false, description: "Latest news standalone"),
        TestCase(query: "What is the Dow Jones at right now?",
                 expectedOffline: false, description: "Dow Jones now"),
        TestCase(query: "What is the current exchange rate for EUR to USD?",
                 expectedOffline: false, description: "Exchange rate current"),
        TestCase(query: "What crypto should I buy right now?",
                 expectedOffline: false, description: "Crypto recommendation now"),
        TestCase(query: "Is the stock market up today?",
                 expectedOffline: false, description: "Market today"),

        // ── Fully offline queries (expect isOfflineCapable == true) ───────────
        TestCase(query: "Explain recursion in programming",
                 expectedOffline: true, description: "Programming concept"),
        TestCase(query: "What is the capital of France?",
                 expectedOffline: true, description: "Geography fact"),
        TestCase(query: "Write a haiku about autumn leaves",
                 expectedOffline: true, description: "Creative writing"),
        TestCase(query: "What is 17 multiplied by 13?",
                 expectedOffline: true, description: "Math"),
        TestCase(query: "Describe the water cycle",
                 expectedOffline: true, description: "Science concept"),
        TestCase(query: "What is Newton's first law of motion?",
                 expectedOffline: true, description: "Physics law"),
        TestCase(query: "Summarize the French Revolution",
                 expectedOffline: true, description: "History"),
        TestCase(query: "What is machine learning?",
                 expectedOffline: true, description: "Technology definition"),
        TestCase(query: "How does photosynthesis work?",
                 expectedOffline: true, description: "Biology"),
        TestCase(query: "What is the Pythagorean theorem?",
                 expectedOffline: true, description: "Math theorem"),
        TestCase(query: "What is the difference between TCP and UDP?",
                 expectedOffline: true, description: "Networking concept"),
        TestCase(query: "Explain the history of the Roman Empire",
                 expectedOffline: true, description: "Historical overview"),
        TestCase(query: "Explain the current best practices for API design",
                 expectedOffline: true, description: "Academic 'current' — not live data"),
        TestCase(query: "What is the theory of evolution?",
                 expectedOffline: true, description: "Scientific theory"),
        TestCase(query: "Write a Python function to reverse a string",
                 expectedOffline: true, description: "Code generation"),
    ]

    // MARK: - Aggregate accuracy test (must pass ≥ 25 / 30)

    func testAtLeast25OutOf30QueriesClassifiedCorrectly() {
        var correct = 0
        var failures: [String] = []

        for tc in testCases {
            let result = classifier.classify(tc.query)
            let gotOffline = result.isOfflineCapable
            if gotOffline == tc.expectedOffline {
                correct += 1
            } else {
                failures.append(
                    "WRONG [\(tc.description)]: '\(tc.query)' " +
                    "expected \(tc.expectedOffline ? "offline" : "live") " +
                    "got \(gotOffline ? "offline" : "live")"
                )
            }
        }

        if !failures.isEmpty {
            print("Classifier misclassifications:")
            failures.forEach { print("  • \($0)") }
        }

        XCTAssertGreaterThanOrEqual(
            correct, 25,
            "\(correct)/\(testCases.count) correct. Need ≥ 25.\nFailures:\n" +
            failures.joined(separator: "\n")
        )
    }

    // MARK: - Individual live-data queries

    func testStockPriceTodayIsLive() {
        XCTAssertFalse(classifier.classify("What is the stock price of Apple today?").isOfflineCapable)
    }

    func testCryptoPriceNowIsLive() {
        XCTAssertFalse(classifier.classify("What is Bitcoin worth right now?").isOfflineCapable)
    }

    func testWeatherTodayIsLive() {
        XCTAssertFalse(classifier.classify("What is the weather like today?").isOfflineCapable)
    }

    func testLatestNewsIsLive() {
        XCTAssertFalse(classifier.classify("What are the latest headlines?").isOfflineCapable)
    }

    func testCurrentInterestRateIsLive() {
        XCTAssertFalse(classifier.classify("What is the current interest rate?").isOfflineCapable)
    }

    // MARK: - Individual offline queries

    func testRecursionExplanationIsOffline() {
        XCTAssertTrue(classifier.classify("Explain recursion in programming").isOfflineCapable)
    }

    func testGeographyIsOffline() {
        XCTAssertTrue(classifier.classify("What is the capital of Japan?").isOfflineCapable)
    }

    func testMathIsOffline() {
        XCTAssertTrue(classifier.classify("What is 144 divided by 12?").isOfflineCapable)
    }

    func testHistoricalTopicIsOffline() {
        XCTAssertTrue(classifier.classify("Summarize the French Revolution").isOfflineCapable)
    }

    func testCodeGenerationIsOffline() {
        XCTAssertTrue(classifier.classify("Write a Python function to sort a list").isOfflineCapable)
    }

    // MARK: - Edge cases

    func testEmptyStringIsOffline() {
        XCTAssertTrue(classifier.classify("").isOfflineCapable)
    }

    func testEmojiOnlyIsOffline() {
        XCTAssertTrue(classifier.classify("🎉🎊🎈").isOfflineCapable)
    }

    func testVeryLongInputDoesNotCrash() {
        let longInput = String(repeating: "explain the concept of recursion ", count: 200)
        XCTAssertNoThrow(classifier.classify(longInput))
    }

    func testOfflineSafeModifierOverridesCurrentKeyword() {
        // "explain the current state of X" is an academic question, not a live request
        let result = classifier.classify("Explain the current state of machine learning research")
        XCTAssertTrue(result.isOfflineCapable,
                      "'explain' modifier should prevent 'current' from triggering live data.")
    }

    func testDescribeCurrentBestPracticesIsOffline() {
        let result = classifier.classify("Describe the current best practices for Swift concurrency")
        XCTAssertTrue(result.isOfflineCapable,
                      "'describe' modifier should prevent 'current' from triggering live data.")
    }

    // MARK: - Result type assertions

    func testLiveResultHasNonEmptyReasonAndSuggestion() {
        let result = classifier.classify("What is the stock price of Tesla today?")
        if case .requiresLiveData(let reason, let suggestion) = result {
            XCTAssertFalse(reason.isEmpty)
            XCTAssertFalse(suggestion.isEmpty)
        } else {
            XCTFail("Expected requiresLiveData but got \(result).")
        }
    }

    func testOfflineResultIsCorrectCase() {
        let result = classifier.classify("What is the Fibonacci sequence?")
        if case .fullyOffline = result {
            // Expected
        } else {
            XCTFail("Expected fullyOffline but got \(result).")
        }
    }
}
