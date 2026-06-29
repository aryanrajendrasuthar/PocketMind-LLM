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

/// Top-level onboarding navigator. Steps: Welcome → Model Selection → Download → Complete.
struct OnboardingFlowView: View {

    @StateObject private var downloadManager = ModelDownloadManager()
    @State private var step: OnboardingStep = .welcome
    @State private var selectedModel: ModelInfo = ModelInfo.recommended(forAvailableRAMGB: deviceRAMGB())
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    enum OnboardingStep {
        case welcome, modelSelection, download, complete
    }

    var body: some View {
        Group {
            switch step {
            case .welcome:
                WelcomeView { step = .modelSelection }
            case .modelSelection:
                ModelSelectionView(selectedModel: $selectedModel) { step = .download }
            case .download:
                ModelDownloadView(model: selectedModel, downloadManager: downloadManager) {
                    step = .complete
                }
            case .complete:
                OnboardingCompleteView(model: selectedModel) {
                    onboardingComplete = true
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: step)
    }
}

// MARK: - RAM detection

private func deviceRAMGB() -> Int {
    let bytes = ProcessInfo.processInfo.physicalMemory
    return Int(bytes / (1024 * 1024 * 1024))
}
