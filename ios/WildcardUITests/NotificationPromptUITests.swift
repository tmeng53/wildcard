import XCTest

/// The notification permission prompt waits for the member's first check-in: nothing at launch,
/// the system prompt once a check-in lands, and never again after it is answered.
///
/// iOS remembers the answer for as long as the app stays installed, so this needs an install
/// that was never asked, as on CI's fresh simulator (`scripts/ios-test.sh` uninstalls the app
/// first).
@MainActor
final class NotificationPromptUITests: XCTestCase {
    private static let wait: TimeInterval = 30
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    func testAskingAfterTheFirstCheckIn() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-photos", "1", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans"]
        app.launch()
        let card = app.descendants(matching: .any).matching(identifier: "today.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: Self.wait), "今天 never appeared")

        let prompt = springboard.alerts.firstMatch
        XCTAssertFalse(prompt.waitForExistence(timeout: 3), "the app asked for notifications before any check-in")

        postHealthyMeal(in: app)
        XCTAssertTrue(prompt.waitForExistence(timeout: Self.wait), "no notification prompt after the first check-in")
        keepScreenshot(named: "29-notification-prompt")
        // The system prompt's second button allows, in any language.
        prompt.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(prompt.waitForNonExistence(timeout: Self.wait), "the prompt stayed up")

        postHealthyMeal(in: app)
        XCTAssertFalse(prompt.waitForExistence(timeout: 4), "the app asked again after it was answered")
    }

    /// 打卡 → 健康餐 → 发布, landing back on the scene.
    private func postHealthyMeal(in app: XCUIApplication) {
        app.buttons["today.checkin"].tap()
        let capsule = app.buttons["today.capsule.healthyMeal"]
        XCTAssertTrue(capsule.waitForExistence(timeout: Self.wait), "no 健康餐 capsule")
        capsule.tap()
        let post = app.buttons["compose.post"]
        XCTAssertTrue(post.waitForExistence(timeout: Self.wait), "the compose page never opened")
        post.tap()
        XCTAssertTrue(post.waitForNonExistence(timeout: Self.wait), "the post didn't land")
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
