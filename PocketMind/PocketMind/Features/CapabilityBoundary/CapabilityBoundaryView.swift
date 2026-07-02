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

import SwiftUI

/// Sheet that explains why a query can't be answered with live data,
/// and lets the user choose to proceed with the model's training knowledge instead.
struct CapabilityBoundaryView: View {

    let capability: QueryCapability
    let onProceed: () -> Void
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 88, height: 88)
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 36))
                        .foregroundStyle(.orange)
                }

                // Title + reason
                VStack(spacing: 10) {
                    Text("Live Data Not Available")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text(reasonText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                // Suggestion card
                if let suggestion {
                    HStack(spacing: 12) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.yellow)
                        Text(suggestion)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    .padding(14)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 24)
                }

                Spacer()

                // Actions
                VStack(spacing: 12) {
                    Button(action: {
                        dismiss()
                        onProceed()
                    }) {
                        Text("Ask with Training Data Only")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 24)

                    Button("Go Back") {
                        dismiss()
                        onDismiss()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss(); onDismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Helpers

    private var reasonText: String {
        switch capability {
        case .requiresLiveData(let reason, _):
            return reason
        case .requiresSearch(let query):
            return "Answering \"\(query)\" requires searching the web, which isn't possible offline."
        case .fullyOffline:
            return ""
        }
    }

    private var suggestion: String? {
        switch capability {
        case .requiresLiveData(_, let s): return s
        case .requiresSearch:             return "Try asking for general background knowledge instead."
        case .fullyOffline:               return nil
        }
    }
}
