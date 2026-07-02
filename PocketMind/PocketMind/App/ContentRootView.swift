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

/// Root routing view: shows onboarding until complete, then the chat interface.
struct ContentRootView: View {

    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @AppStorage("selectedModelId") private var selectedModelId = ""

    var body: some View {
        if onboardingComplete, let model = resolvedModel {
            ChatView(viewModel: ChatViewModel(modelInfo: model))
                .transition(.opacity)
        } else {
            OnboardingFlowView()
                .transition(.opacity)
                .onAppear {
                    // Dev bypass — skip CDN download
                    UserDefaults.standard.set(true, forKey: "onboardingComplete")
                    UserDefaults.standard.set("pocketmind_llama32_1b-coreml", forKey: "selectedModelId")
                }
        }
    }                              // ← body closes HERE

    private var resolvedModel: ModelInfo? {    // ← outside body, inside struct
        ModelInfo.allModels.first(where: { $0.id == selectedModelId })
            ?? ModelInfo.allModels.first
    }
}
