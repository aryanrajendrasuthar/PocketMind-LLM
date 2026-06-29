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

struct WelcomeView: View {

    let onContinue: () -> Void

    private let privacyPoints: [(icon: String, title: String, body: String)] = [
        ("lock.shield.fill",    "Fully Private",      "Your conversations never leave your iPhone."),
        ("wifi.slash",          "No Internet Needed", "All AI runs on your device — no cloud required."),
        ("eye.slash.fill",      "Zero Data Collected","No analytics, no telemetry, no account required."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // App icon + name
            VStack(spacing: 16) {
                Image(systemName: "brain.filled.head.profile")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)
                    .symbolEffect(.pulse, options: .repeating)

                Text("PocketMind")
                    .font(.largeTitle.bold())

                Text("Private, offline AI on your iPhone.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Spacer()

            // Privacy points
            VStack(spacing: 20) {
                ForEach(privacyPoints, id: \.title) { point in
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: point.icon)
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(point.title).font(.headline)
                            Text(point.body).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            Button(action: onContinue) {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }
}
