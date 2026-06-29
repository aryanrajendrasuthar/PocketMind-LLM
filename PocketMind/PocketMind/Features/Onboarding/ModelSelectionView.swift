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

struct ModelSelectionView: View {

    @Binding var selectedModel: ModelInfo
    let onContinue: () -> Void

    private let availableRAM = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Choose Your Model")
                    .font(.largeTitle.bold())
                Text("We recommended one for your device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 56)
            .padding(.horizontal, 24)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(ModelInfo.allModels) { model in
                        ModelCardView(
                            model: model,
                            isSelected: selectedModel.id == model.id,
                            isRecommended: ModelInfo.recommended(forAvailableRAMGB: availableRAM).id == model.id,
                            isCompatible: model.isCompatible(withAvailableRAMGB: availableRAM)
                        ) {
                            if model.isCompatible(withAvailableRAMGB: availableRAM) {
                                selectedModel = model
                            }
                        }
                    }
                }
                .padding(24)
            }

            Button(action: onContinue) {
                Text("Download \(selectedModel.displayName)")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Model card

private struct ModelCardView: View {
    let model: ModelInfo
    let isSelected: Bool
    let isRecommended: Bool
    let isCompatible: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(model.displayName).font(.headline)
                            if isRecommended {
                                Text("Recommended")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.blue.opacity(0.15))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            }
                        }
                        Text(model.minDevice + " or newer · " + model.quantization)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? .blue : .secondary)
                        .font(.title3)
                }

                HStack(spacing: 16) {
                    Label(String(format: "%.1f GB", model.fileSizeGB), systemImage: "externaldrive.fill")
                    Label(speedLabel, systemImage: "bolt.fill")
                    Label(qualityLabel, systemImage: "star.fill")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
            )
            .opacity(isCompatible ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!isCompatible)
    }

    private var speedLabel: String {
        switch model.id {
        case let id where id.contains("1b"): return "Fastest"
        case let id where id.contains("3b"): return "Balanced"
        default:                             return "Slower"
        }
    }

    private var qualityLabel: String {
        switch model.id {
        case let id where id.contains("1b"):  return "Good"
        case let id where id.contains("3b"):  return "Better"
        default:                              return "Best"
        }
    }
}
