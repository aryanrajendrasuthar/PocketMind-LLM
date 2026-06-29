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

import CryptoKit
import Foundation
import os.log

/// Manages model file downloads with background URLSession, SHA-256 verification,
/// and certificate pinning.
///
/// Models are stored in `Application Support/models/<modelId>/` and excluded from backup.
@MainActor
final class ModelDownloadManager: NSObject, ObservableObject {

    // MARK: - Published state

    @Published var downloadProgress: [String: Double] = [:]
    @Published var downloadedModels: Set<String> = []
    @Published var activeDownloads: Set<String> = []
    @Published var downloadError: [String: String] = [:]

    // MARK: - Private state

    private var session: URLSession?
    private var taskMap: [URLSessionTask: String] = [:]  // task → modelId
    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "ModelDownloadManager")

    // MARK: - Init

    override init() {
        super.init()
        setupSession()
        refreshDownloadedModels()
    }

    // MARK: - Public API

    /// Start downloading a model. Resumes an interrupted download automatically.
    func startDownload(_ model: ModelInfo) {
        guard !activeDownloads.contains(model.id) else { return }
        guard let session else { return }

        // Reject cellular downloads unless explicitly allowed
        let allowsCellular = UserDefaults.standard.bool(forKey: "allowsCellularDownload")
        if !allowsCellular {
            let connectionType = NetworkMonitor.shared.connectionType
            if connectionType == .cellular {
                downloadError[model.id] = "Wi-Fi required for model downloads. Enable cellular in Settings."
                return
            }
        }

        let url = manifestURL(for: model.id)
        logger.info("Starting download: \(model.displayName, privacy: .public)")

        let task = session.downloadTask(with: url)
        taskMap[task] = model.id
        activeDownloads.insert(model.id)
        downloadProgress[model.id] = 0
        downloadError.removeValue(forKey: model.id)
        task.resume()
    }

    /// Cancel an in-progress download.
    func cancelDownload(_ modelId: String) {
        taskMap.first(where: { $0.value == modelId })?.key.cancel()
        activeDownloads.remove(modelId)
        downloadProgress.removeValue(forKey: modelId)
    }

    /// Returns true if the model file is present and its SHA-256 matches `expectedSHA256`.
    func isModelReady(_ model: ModelInfo) -> Bool {
        let dir = modelDirectory(for: model.id)
        guard FileManager.default.fileExists(atPath: dir.path) else { return false }
        // If no sha256 in manifest yet, treat presence as ready
        guard !model.sha256.isEmpty else { return true }
        return (try? verifyDirectory(dir, expectedSHA256: model.sha256)) ?? false
    }

    /// Path to the .mlpackage directory for the given model ID.
    func modelURL(for modelId: String) -> URL {
        modelDirectory(for: modelId)
    }

    // MARK: - URLSession setup

    private func setupSession() {
        let config = URLSessionConfiguration.background(withIdentifier: "com.aryan.pocketmind.download")
        config.isDiscretionary = false
        config.allowsCellularAccess = UserDefaults.standard.bool(forKey: "allowsCellularDownload")
        config.timeoutIntervalForResource = 3600 * 6  // 6h for large model files
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    // MARK: - File system

    private func modelDirectory(for modelId: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent(Constants.Storage.modelsDirectory)
            .appendingPathComponent(modelId)
    }

    private func manifestURL(for modelId: String) -> URL {
        URL(string: "\(Constants.ModelDownload.manifestBaseURL)/\(modelId)/\(Constants.ModelDownload.manifestFilename)")!
    }

    private func refreshDownloadedModels() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Constants.Storage.modelsDirectory)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: base, includingPropertiesForKeys: nil
        ) else { return }
        downloadedModels = Set(contents.map(\.lastPathComponent))
    }

    private func finalizeDownload(modelId: String, tempURL: URL) {
        let destDir = modelDirectory(for: modelId)
        do {
            try FileManager.default.createDirectory(at: destDir.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destDir.path) {
                try FileManager.default.removeItem(at: destDir)
            }
            try FileManager.default.moveItem(at: tempURL, to: destDir)
            try applyBackupExclusion(to: destDir)
            logger.info("Model \(modelId, privacy: .public) installed at \(destDir.path, privacy: .private).")
            Task { @MainActor in
                downloadedModels.insert(modelId)
                activeDownloads.remove(modelId)
                downloadProgress[modelId] = 1.0
            }
        } catch {
            logger.error("Failed to install model \(modelId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            Task { @MainActor in
                downloadError[modelId] = "Installation failed. Please try again."
                activeDownloads.remove(modelId)
            }
        }
    }

    private func applyBackupExclusion(to url: URL) throws {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
    }

    // MARK: - SHA-256 verification

    private func verifyDirectory(_ dir: URL, expectedSHA256: String) throws -> Bool {
        let sha = try computeDirectorySHA256(dir)
        return sha.lowercased() == expectedSHA256.lowercased()
    }

    private func computeDirectorySHA256(_ dir: URL) throws -> String {
        var hasher = SHA256()
        let files = try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }

        for file in files {
            hasher.update(data: Data(file.lastPathComponent.utf8))
            let data = try Data(contentsOf: file)
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - URLSessionDownloadDelegate

extension ModelDownloadManager: URLSessionDownloadDelegate {

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let modelId = taskMap[downloadTask] else { return }

        Task { @MainActor in
            finalizeDownload(modelId: modelId, tempURL: location)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let modelId = taskMap[downloadTask], totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in
            downloadProgress[modelId] = progress
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error, let modelId = taskMap[task] else { return }
        let message = (error as NSError).code == NSURLErrorCancelled
            ? nil
            : error.localizedDescription
        Task { @MainActor in
            activeDownloads.remove(modelId)
            if let message {
                downloadError[modelId] = message
            }
        }
    }

    // MARK: - Certificate pinning

    nonisolated func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Evaluate default trust first
        var error: CFError?
        let trusted = SecTrustEvaluateWithError(serverTrust, &error)
        guard trusted else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Leaf certificate public key hash pinning
        guard let pinnedHash = Bundle.main.object(forInfoDictionaryKey: "PinnedCDNPublicKeyHash") as? String,
              !pinnedHash.isEmpty
        else {
            // Pinning hash not configured — accept valid TLS (development only)
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
            return
        }

        guard let leaf = SecTrustGetCertificateAtIndex(serverTrust, 0),
              let publicKey = SecCertificateCopyKey(leaf),
              let keyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?
        else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let digest = SHA256.hash(data: keyData)
        let actualHash = digest.map { String(format: "%02x", $0) }.joined()

        if actualHash == pinnedHash {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            Logger(subsystem: Constants.bundleIdentifier, category: "ModelDownloadManager")
                .error("Certificate pin mismatch. Download aborted.")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

// MARK: - Network monitor stub

/// Lightweight connectivity observer (replaced by NWPathMonitor in production).
private final class NetworkMonitor {
    static let shared = NetworkMonitor()
    enum ConnectionType { case wifi, cellular, none }
    var connectionType: ConnectionType { .wifi }  // default; wired up via NWPathMonitor in Sprint 6
}
