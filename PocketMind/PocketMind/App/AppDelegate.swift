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

import UIKit
import os.log

final class AppDelegate: NSObject, UIApplicationDelegate {

    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "AppDelegate")

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        logger.info("PocketMind launched.")
        NetworkMonitor.shared.start()
        return true
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        logger.warning("System memory warning received.")
    }
}
