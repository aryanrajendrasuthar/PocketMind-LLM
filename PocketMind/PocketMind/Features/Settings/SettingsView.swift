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

struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss

    // Inference
    @AppStorage("inferenceTemperature") private var temperature: Double = Double(Constants.Inference.defaultTemperature)
    @AppStorage("inferenceTopP")        private var topP: Double = Double(Constants.Inference.defaultTopP)
    @AppStorage("inferenceMaxTokens")   private var maxTokens: Int = Constants.Inference.defaultMaxTokens

    // Privacy / network
    @AppStorage("allowsCellularDownload") private var allowsCellular = false

    // Appearance
    @AppStorage("preferredColorScheme") private var colorScheme = 0  // 0 = system, 1 = light, 2 = dark

    // Danger zone
    @State private var showDeleteConfirmation = false
    @State private var vault: PrivacyVault?

    var body: some View {
        NavigationStack {
            List {
                // MARK: Model
                Section("Model") {
                    NavigationLink("Change Model") {
                        ChangeModelView()
                    }
                }

                // MARK: Inference
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Temperature")
                            Spacer()
                            Text(String(format: "%.2f", temperature))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $temperature, in: 0...2, step: 0.05)
                            .tint(.blue)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Top-P")
                            Spacer()
                            Text(String(format: "%.2f", topP))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $topP, in: 0.5...1.0, step: 0.05)
                            .tint(.blue)
                    }
                    .padding(.vertical, 4)

                    Stepper("Max Tokens: \(maxTokens)", value: $maxTokens, in: 64...2048, step: 64)
                } header: {
                    Text("Inference")
                } footer: {
                    Text("Higher temperature = more creative but less predictable responses.")
                }

                // MARK: Privacy
                Section("Privacy") {
                    Toggle("Allow Cellular Downloads", isOn: $allowsCellular)
                    NavigationLink("Privacy Architecture") {
                        PrivacyInfoView()
                    }
                }

                // MARK: Appearance
                Section("Appearance") {
                    Picker("Color Scheme", selection: $colorScheme) {
                        Text("System").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    }
                    .pickerStyle(.segmented)
                }

                // MARK: About
                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Model API", value: "On-Device Only")
                    LabeledContent("Data Collection", value: "None")
                }

                // MARK: Danger zone
                Section {
                    Button("Delete All Conversations", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Deletes all encrypted conversation data from this device. This cannot be undone.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Delete All Conversations?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive) {
                    Task {
                        try? await vault?.deleteAllData()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all conversations from this device.")
            }
        }
        .preferredColorScheme(preferredScheme)
        .task { vault = try? await PrivacyVault() }
    }

    private var preferredScheme: ColorScheme? {
        switch colorScheme {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

// MARK: - Change model placeholder

private struct ChangeModelView: View {
    private let availableRAM = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
    @State private var selected: ModelInfo = ModelInfo.recommended(forAvailableRAMGB: Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)))
    @StateObject private var downloadManager = ModelDownloadManager()

    var body: some View {
        List {
            ForEach(ModelInfo.allModels) { model in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.displayName).font(.headline)
                        Text("\(String(format: "%.1f", model.fileSizeGB)) GB · \(model.quantization)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if downloadManager.downloadedModels.contains(model.id) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Download") { downloadManager.startDownload(model) }
                            .font(.subheadline)
                            .buttonStyle(.bordered)
                            .disabled(!model.isCompatible(withAvailableRAMGB: availableRAM))
                    }
                }
            }
        }
        .navigationTitle("Change Model")
    }
}

// MARK: - Privacy info view

private struct PrivacyInfoView: View {
    private let dataRows: [(String, String)] = [
        ("Conversations",   "Stored on-device only, encrypted"),
        ("Model files",     "Stored on-device only, excluded from backup"),
        ("Network access",  "None during inference"),
        ("Analytics",       "None"),
        ("Crash reporting", "None"),
        ("Account",         "Not required"),
    ]

    var body: some View {
        List {
            Section("What's On Your Device") {
                ForEach(dataRows, id: \.0) { label, value in
                    LabeledContent(label, value: value)
                }
            }
            Section {
                Label("Secure Enclave key derivation", systemImage: "lock.shield.fill")
                Label("SQLCipher database encryption", systemImage: "cylinder.split.1x2.fill")
                Label("Excluded from iCloud backup", systemImage: "icloud.slash.fill")
            } header: {
                Text("Privacy Features")
            }
        }
        .navigationTitle("Privacy Architecture")
    }
}
