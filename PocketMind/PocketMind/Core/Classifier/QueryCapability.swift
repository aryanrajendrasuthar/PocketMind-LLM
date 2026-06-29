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

/// The result of classifying a user query through `CapabilityBoundaryClassifier`.
enum QueryCapability: Sendable, Equatable {

    /// The model can answer this fully offline from training knowledge.
    case fullyOffline

    /// The query requires live data that the model cannot have.
    /// - Parameters:
    ///   - reason: A user-facing sentence explaining what kind of live data is needed.
    ///   - suggestion: A concrete alternative the user can try (e.g. "Open Safari for live prices").
    case requiresLiveData(reason: String, suggestion: String)

    /// The query could benefit from a real-time search but the model may still attempt it.
    /// - Parameter query: The reformulated search query to suggest to the user.
    case requiresSearch(query: String)

    static func == (lhs: QueryCapability, rhs: QueryCapability) -> Bool {
        switch (lhs, rhs) {
        case (.fullyOffline, .fullyOffline):
            return true
        case (.requiresLiveData(let r1, let s1), .requiresLiveData(let r2, let s2)):
            return r1 == r2 && s1 == s2
        case (.requiresSearch(let q1), .requiresSearch(let q2)):
            return q1 == q2
        default:
            return false
        }
    }

    /// `true` if the query can be served without a live-data warning.
    var isOfflineCapable: Bool {
        switch self {
        case .fullyOffline: return true
        case .requiresLiveData, .requiresSearch: return false
        }
    }
}
