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

import XCTest

/// UI smoke tests for the onboarding flow.
/// These tests assume a fresh install state (no prior `onboardingComplete` flag).
final class OnboardingUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // Reset onboarding state so tests always start from step 1.
        app.launchArguments = ["--uitesting", "--reset-onboarding"]
        app.launch()
    }

    override func tearDown() {
        app.terminate()
        super.tearDown()
    }

    // MARK: - Welcome screen

    func testWelcomeScreenAppearsOnFreshInstall() {
        XCTAssertTrue(app.staticTexts["PocketMind"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Private, offline AI on your iPhone."].exists)
    }

    func testWelcomeScreenShowsPrivacyPoints() {
        XCTAssertTrue(app.staticTexts["Fully Private"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No Internet Needed"].exists)
        XCTAssertTrue(app.staticTexts["Zero Data Collected"].exists)
    }

    func testGetStartedButtonExists() {
        XCTAssertTrue(app.buttons["Get Started"].waitForExistence(timeout: 5))
    }

    func testGetStartedNavigatesToModelSelection() {
        app.buttons["Get Started"].tap()
        XCTAssertTrue(app.staticTexts["Choose Your Model"].waitForExistence(timeout: 3))
    }

    // MARK: - Model selection screen

    func testModelSelectionShowsAllThreeModels() {
        app.buttons["Get Started"].tap()
        XCTAssertTrue(app.staticTexts["Llama 3.2 1B"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Llama 3.2 3B"].exists)
        XCTAssertTrue(app.staticTexts["Phi-3 Mini 3.8B"].exists)
    }

    func testModelSelectionShowsRecommendedBadge() {
        app.buttons["Get Started"].tap()
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Recommended'"))
                .firstMatch.waitForExistence(timeout: 3)
        )
    }

    func testModelSelectionDownloadButtonContainsModelName() {
        app.buttons["Get Started"].tap()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Download'"))
                .firstMatch.waitForExistence(timeout: 3)
        )
    }
}
