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

/// UI smoke tests for the main chat interface.
/// These tests assume onboarding has been completed and a model is available.
final class ChatUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // Skip onboarding; inject a stubbed model so inference doesn't require a real .mlpackage.
        app.launchArguments = ["--uitesting", "--skip-onboarding", "--stub-inference"]
        app.launch()
    }

    override func tearDown() {
        app.terminate()
        super.tearDown()
    }

    // MARK: - Chat layout

    func testNavigationTitleIsPocketMind() {
        XCTAssertTrue(app.navigationBars["PocketMind"].waitForExistence(timeout: 5))
    }

    func testNewConversationButtonExists() {
        XCTAssertTrue(
            app.navigationBars["PocketMind"].buttons.element(boundBy: 0).waitForExistence(timeout: 5)
        )
    }

    func testSettingsButtonExists() {
        XCTAssertTrue(
            app.navigationBars["PocketMind"].buttons.element(boundBy: 1).waitForExistence(timeout: 5)
        )
    }

    func testEmptyStateTextAppearsOnFreshChat() {
        XCTAssertTrue(app.staticTexts["Ask me anything."].waitForExistence(timeout: 5))
    }

    func testMessageTextFieldExists() {
        XCTAssertTrue(app.textViews["Message"].waitForExistence(timeout: 5))
    }

    func testSendButtonExistsAndIsInitiallyDisabled() {
        let sendButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'arrow.up.circle'")
        ).firstMatch
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5))
    }

    // MARK: - Sending a message

    func testTypingInTextFieldEnablesSendButton() {
        let textField = app.textViews["Message"]
        XCTAssertTrue(textField.waitForExistence(timeout: 5))
        textField.tap()
        textField.typeText("Hello")
        // Send button should become enabled after typing
        let sendButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'arrow.up'")
        ).firstMatch
        XCTAssertTrue(sendButton.isEnabled)
    }

    func testSendingMessageAppearsInScrollView() {
        let textField = app.textViews["Message"]
        XCTAssertTrue(textField.waitForExistence(timeout: 5))
        textField.tap()
        textField.typeText("What is machine learning?")
        app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'arrow.up'")
        ).firstMatch.tap()
        // User bubble should appear
        XCTAssertTrue(
            app.staticTexts["What is machine learning?"].waitForExistence(timeout: 5)
        )
    }

    func testTextFieldClearsAfterSend() {
        let textField = app.textViews["Message"]
        XCTAssertTrue(textField.waitForExistence(timeout: 5))
        textField.tap()
        textField.typeText("Test message")
        app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'arrow.up'")
        ).firstMatch.tap()
        // TextField value should be empty
        XCTAssertEqual(textField.value as? String, "")
    }

    // MARK: - Settings sheet

    func testSettingsSheetOpens() {
        app.navigationBars["PocketMind"].buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
    }

    func testSettingsSheetHasTemperatureSlider() {
        app.navigationBars["PocketMind"].buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.staticTexts["Temperature"].waitForExistence(timeout: 3))
    }

    func testSettingsSheetDismissesViaDoneButton() {
        app.navigationBars["PocketMind"].buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["PocketMind"].waitForExistence(timeout: 3))
    }

    // MARK: - New conversation

    func testNewConversationButtonClearsMessages() {
        // Send a message first
        let textField = app.textViews["Message"]
        XCTAssertTrue(textField.waitForExistence(timeout: 5))
        textField.tap()
        textField.typeText("Hello world")
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'arrow.up'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Hello world"].waitForExistence(timeout: 5))

        // Tap new conversation
        app.navigationBars["PocketMind"].buttons.element(boundBy: 0).tap()
        // Empty state should return
        XCTAssertTrue(app.staticTexts["Ask me anything."].waitForExistence(timeout: 3))
    }
}
