import XCTest

/// The loaders a fast load never shows long enough to see: the launch cover with the two tickets
/// rocking, the same over a slow sign-in, and 三拍 in the style guide's buttons. Screenshots are
/// kept to compare with the approved design.
@MainActor
final class LoadingUITests: XCTestCase {
    /// Slow CI simulators can take many seconds to show a screen; a real failure still fails.
    private static let wait: TimeInterval = 30

    func testTheLaunchCoverRocks() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-loading",
        ]
        app.launch()
        let loader = app.descendants(matching: .any).matching(identifier: "launch.cover").firstMatch
        let shown = loader.waitForExistence(timeout: Self.wait)
        if !shown { print(app.debugDescription) }
        // Kept either way, so a failure still shows what the page drew.
        Thread.sleep(forTimeInterval: 0.6)
        keepScreenshot(named: "90-launch-cover")
        XCTAssertTrue(shown, "the launch cover never showed")
        XCTAssertEqual(loader.label, "加载中")
    }

    /// A slow sign-in on the open screen: the loader covers it, then the editor opens.
    func testASlowSignInIsCovered() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-onboarding",
            "-slow-sign-in",
        ]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        let signIn = app.buttons["signup.signIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: Self.wait), "the open screen never appeared")
        signIn.tap()
        let cover = app.descendants(matching: .any).matching(identifier: "loading.cover").firstMatch
        XCTAssertTrue(cover.waitForExistence(timeout: Self.wait), "a slow sign-in showed no loader")
        XCTAssertEqual(cover.label, "加载中")
        XCTAssertTrue(app.buttons["editor.done"].waitForExistence(timeout: Self.wait), "the editor never opened")
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: cover)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: Self.wait), .completed, "the loader stayed up")
    }

    func testDotsInTheStyleGuide() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-styleguide",
        ]
        app.launch()
        // The gym, the default scene, as the approved design is drawn on it.
        let gym = app.buttons["styleguide.scene.gym"]
        XCTAssertTrue(gym.waitForExistence(timeout: Self.wait), "the style guide never appeared")
        gym.tap()
        let group = app.descendants(matching: .any).matching(identifier: "styleguide.loading").firstMatch
        // Swipe until the whole group is on screen, clear of the bottom edge.
        let window = app.windows.firstMatch
        for _ in 0..<20 where !(group.exists && group.frame.maxY <= window.frame.maxY - 60) {
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(group.isHittable, "the style guide has no 三拍 group")
        Thread.sleep(forTimeInterval: 0.6)
        keepScreenshot(named: "91-loading-dots")
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
