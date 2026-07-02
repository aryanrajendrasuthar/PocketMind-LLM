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

struct OnboardingCompleteView: View {

    let model: ModelInfo
    let onEnterApp: () -> Void

    @AppStorage("selectedModelId") private var selectedModelId = ""

    private let summaryPoints: [(String, String)] = [
        ("brain.filled.head.profile", "Runs entirely on your iPhone"),
        ("lock.fill",                 "Conversations encrypted with Secure Enclave"),
        ("wifi.slash",                "No internet needed — ever"),
        ("hand.raised.fill",          "Zero data collected or shared"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.green)

                VStack(spacing: 8) {
                    Text("You're All Set")
                        .font(.largeTitle.bold())
                    Text("\(model.displayName) is ready.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                ForEach(summaryPoints, id: \.0) { icon, label in
                    HStack(spacing: 14) {
                        Image(systemName: icon)
                            .font(.title3)
                            .foregroundStyle(.blue)
                            .frame(width: 28)
                        Text(label).font(.subheadline)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            Button(action: {
                selectedModelId = model.id
                onEnterApp()
            }) {
                Text("Start Chatting")
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
