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

/// Root navigation controller — replaced in Sprint 5 with full OnboardingFlow / ChatView.
struct ContentRootView: View {

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "brain")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)
                Text("PocketMind")
                    .font(.largeTitle.bold())
                Text("Private, offline AI on your iPhone.")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("PocketMind")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
