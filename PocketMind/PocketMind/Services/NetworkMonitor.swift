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

import Network
import os.log

/// Observes network reachability via `NWPathMonitor`. Lightweight singleton — start once at launch.
final class NetworkMonitor: @unchecked Sendable {

    static let shared = NetworkMonitor()

    enum ConnectionType: Equatable {
        case wifi
        case ethernet
        case cellular
        case none
    }

    private(set) var connectionType: ConnectionType = .none
    private(set) var isReachable = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.aryan.pocketmind.network", qos: .utility)
    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "NetworkMonitor")

    private init() {}

    /// Begin monitoring. Call once from `AppDelegate.application(_:didFinishLaunchingWithOptions:)`.
    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.isReachable = path.status == .satisfied
            self.connectionType = self.resolveType(path)
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }

    // MARK: - Private

    private func resolveType(_ path: NWPath) -> ConnectionType {
        guard path.status == .satisfied else { return .none }
        if path.usesInterfaceType(.wifi)     { return .wifi }
        if path.usesInterfaceType(.wiredEthernet) { return .ethernet }
        if path.usesInterfaceType(.cellular) { return .cellular }
        return .none
    }
}
