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

/// Static rule tables used by `CapabilityBoundaryClassifier` Stage 1.
///
/// Rules are grouped by live-data category. A query triggers `.requiresLiveData`
/// when it contains both:
///   - a **temporal trigger word** (e.g. "today", "current", "right now"), AND
///   - a **domain noun** from that category (e.g. "price", "weather", "score")
///
/// Some domain nouns are strong enough signals on their own (marked as standalone).
enum ClassifierRules {

    // MARK: - Temporal trigger words

    /// Words that signal a desire for present or near-present information.
    static let temporalTriggers: Set<String> = [
        "today", "tonight", "now", "right now", "currently", "current",
        "latest", "live", "real-time", "realtime", "this week", "this month",
        "at the moment", "as of", "recent", "recently", "last night",
        "yesterday", "tomorrow", "forecast", "upcoming", "soon",
        "just", "breaking", "new", "update", "updated",
    ]

    // MARK: - Category rule tables

    /// Each entry: (domainNouns, standaloneNouns, reason, suggestion)
    /// - `domainNouns`: require a temporal trigger to fire
    /// - `standaloneNouns`: fire without a temporal trigger
    struct CategoryRule {
        let domainNouns: Set<String>
        let standaloneNouns: Set<String>
        let reason: String
        let suggestion: String
    }

    static let categories: [CategoryRule] = [

        // Finance
        CategoryRule(
            domainNouns: ["price", "prices", "value", "worth", "rate", "rates",
                          "cost", "market", "trading", "trade"],
            standaloneNouns: ["stock price", "crypto price", "bitcoin price", "ethereum price",
                              "share price", "market cap", "stock market", "nasdaq", "dow jones",
                              "s&p", "sp500", "nyse", "coin price", "token price"],
            reason: "Stock and crypto prices change by the second — PocketMind's training data is from a fixed date.",
            suggestion: "Open a finance app or Safari for live prices."
        ),

        // Weather
        CategoryRule(
            domainNouns: ["weather", "temperature", "rain", "snow", "wind", "humidity",
                          "storm", "hurricane", "tornado", "forecast", "sunny", "cloudy",
                          "degrees", "celsius", "fahrenheit"],
            standaloneNouns: ["weather today", "weather tonight", "weather this week"],
            reason: "Weather requires a live forecast — PocketMind has no internet access.",
            suggestion: "Ask Siri or open the Weather app for current conditions."
        ),

        // News and events
        CategoryRule(
            domainNouns: ["news", "headline", "headlines", "story", "stories", "event",
                          "election", "vote", "result", "results", "winner", "who won",
                          "happened", "happening", "announcement"],
            standaloneNouns: ["breaking news", "latest news", "today's news", "news today"],
            reason: "News and current events require live data — PocketMind's knowledge has a cutoff date.",
            suggestion: "Check a news app, Safari, or Apple News for current stories."
        ),

        // Sports
        CategoryRule(
            domainNouns: ["score", "scores", "game", "match", "standings", "ranking",
                          "playoff", "championship", "season", "tournament", "league",
                          "nfl", "nba", "mlb", "nhl", "mls", "fifa", "ufc", "tennis",
                          "goal", "points", "win", "loss", "draft"],
            standaloneNouns: ["sports scores", "game score", "final score", "who won the game",
                              "last night's game", "tonight's game"],
            reason: "Sports scores and results require a live data feed.",
            suggestion: "Check the ESPN app, Apple Sports, or Safari for scores."
        ),

        // Business information
        CategoryRule(
            domainNouns: ["hours", "open", "closed", "closing", "location", "address",
                          "phone", "number", "contact", "directions", "menu", "reservation"],
            standaloneNouns: ["store hours", "business hours", "is it open", "is open today",
                              "phone number", "opening time", "closing time"],
            reason: "Business hours and contact info change and require a live lookup.",
            suggestion: "Use Maps or Safari to look up current hours and contact details."
        ),

        // Real estate and rates
        CategoryRule(
            domainNouns: ["mortgage", "interest rate", "apr", "loan rate", "home price",
                          "house price", "property value", "rent", "rental price"],
            standaloneNouns: ["current mortgage rate", "today's interest rate", "current interest rate"],
            reason: "Interest and mortgage rates change daily and require live data.",
            suggestion: "Check your bank's app or a financial site for current rates."
        ),
    ]

    // MARK: - Explicit standalone phrases (override without temporal trigger check)

    /// Multi-word phrases that definitively require live data regardless of surrounding context.
    static let explicitLivePhrases: Set<String> = [
        "what is the weather",
        "how is the weather",
        "what's the weather",
        "weather in",
        "weather for",
        "stock price",
        "share price",
        "crypto price",
        "bitcoin price",
        "ethereum price",
        "what is bitcoin",
        "how much is bitcoin",
        "exchange rate",
        "currency rate",
        "who won",
        "what's the score",
        "what is the score",
        "sports scores",
        "game score",
        "is the market",
        "market today",
        "breaking news",
        "latest news",
        "news today",
        "today's news",
        "store hours",
        "business hours",
        "is it open",
        "is open today",
    ]

    // MARK: - Offline-safe modifiers

    /// When one of these words precedes a temporal trigger, the query is likely academic
    /// rather than a live-data request. E.g. "explain the current state of machine learning"
    /// is a knowledge question, not a real-time request.
    static let offlineSafeModifiers: Set<String> = [
        "explain", "describe", "what is", "what are", "define", "definition",
        "history of", "history", "background", "overview", "concept", "theory",
        "how does", "why does", "why is", "example", "examples",
        "teach", "learn", "understand", "basics", "introduction",
        "compare", "comparison", "difference between", "pros and cons",
    ]
}
