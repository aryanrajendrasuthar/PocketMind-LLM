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

/// Animated three-dot typing indicator shown while the model is generating.
struct TypingIndicatorView: View {

    @State private var phase: Double = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 8)
                        .scaleEffect(dotScale(for: index))
                        .animation(
                            .easeInOut(duration: 0.4)
                                .repeatForever()
                                .delay(Double(index) * 0.15),
                            value: phase
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))

            Spacer(minLength: 48)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        .onAppear { phase = 1 }
    }

    private func dotScale(for index: Int) -> CGFloat {
        // offset each dot so the phase arrives staggered
        let offset = Double(index) * 0.15
        let localPhase = (phase + offset).truncatingRemainder(dividingBy: 1.0)
        return localPhase < 0.5 ? (0.6 + localPhase * 0.8) : (1.0 - (localPhase - 0.5) * 0.8)
    }
}
