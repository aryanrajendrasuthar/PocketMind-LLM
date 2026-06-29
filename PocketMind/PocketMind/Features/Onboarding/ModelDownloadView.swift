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

struct ModelDownloadView: View {

    let model: ModelInfo
    @ObservedObject var downloadManager: ModelDownloadManager
    let onComplete: () -> Void

    @State private var phase: Phase = .idle

    enum Phase { case idle, downloading, verifying, done, failed(String) }

    private var progress: Double { downloadManager.downloadProgress[model.id] ?? 0 }
    private var errorMessage: String? { downloadManager.downloadError[model.id] }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 96, height: 96)
                    Image(systemName: phaseIcon)
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)
                        .symbolEffect(.pulse, isActive: phase == .downloading)
                }

                Text(phaseTitle)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(phaseSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            // Progress section
            VStack(spacing: 16) {
                if case .downloading = phase {
                    VStack(spacing: 8) {
                        ProgressView(value: progress)
                            .tint(.blue)
                        HStack {
                            Text(String(format: "%.0f%%", progress * 100))
                                .font(.caption.monospacedDigit())
                            Spacer()
                            Text(String(format: "%.1f / %.1f GB",
                                        progress * model.fileSizeGB,
                                        model.fileSizeGB))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 32)
                }

                if case .verifying = phase {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("Verifying SHA-256…").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Action button
            VStack(spacing: 12) {
                if case .failed(let msg) = phase {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button(action: handleAction) {
                    Text(actionLabel)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 32)
                .disabled(phase == .verifying)

                if case .downloading = phase {
                    Button("Cancel") {
                        downloadManager.cancelDownload(model.id)
                        phase = .idle
                    }
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                }
            }
            .padding(.bottom, 40)
        }
        .onChange(of: downloadManager.downloadedModels) { _, downloaded in
            if downloaded.contains(model.id) {
                phase = .verifying
                Task {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    phase = .done
                }
            }
        }
        .onChange(of: downloadManager.downloadError) { _, errors in
            if let msg = errors[model.id] {
                phase = .failed(msg)
            }
        }
        .onChange(of: phase) { _, newPhase in
            if case .done = newPhase { onComplete() }
        }
        .onAppear {
            if downloadManager.isModelReady(model) {
                phase = .done
            }
        }
    }

    // MARK: - Helpers

    private var phaseIcon: String {
        switch phase {
        case .idle:        return "arrow.down.circle"
        case .downloading: return "arrow.down.circle.fill"
        case .verifying:   return "checkmark.shield"
        case .done:        return "checkmark.circle.fill"
        case .failed:      return "exclamationmark.triangle"
        }
    }

    private var phaseTitle: String {
        switch phase {
        case .idle:        return "Ready to Download"
        case .downloading: return "Downloading \(model.displayName)"
        case .verifying:   return "Verifying"
        case .done:        return "All Set!"
        case .failed:      return "Download Failed"
        }
    }

    private var phaseSubtitle: String {
        switch phase {
        case .idle:
            return "\(model.displayName) is \(String(format: "%.1f", model.fileSizeGB)) GB. " +
                   "Download once — runs offline forever."
        case .downloading:
            return "Keep PocketMind open while downloading."
        case .verifying:
            return "Checking file integrity…"
        case .done:
            return "\(model.displayName) is ready to use."
        case .failed:
            return "Something went wrong. Tap Retry to try again."
        }
    }

    private var actionLabel: String {
        switch phase {
        case .idle:        return "Download (\(String(format: "%.1f", model.fileSizeGB)) GB)"
        case .downloading: return "Downloading…"
        case .verifying:   return "Verifying…"
        case .done:        return "Continue"
        case .failed:      return "Retry"
        }
    }

    private func handleAction() {
        switch phase {
        case .idle, .failed:
            downloadManager.startDownload(model)
            phase = .downloading
        case .done:
            onComplete()
        default:
            break
        }
    }
}
