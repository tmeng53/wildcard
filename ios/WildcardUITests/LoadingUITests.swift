import XCTest

/// The loaders of design A, which a fast load never shows long enough to see: the launch page
/// with the character jogging, and 三拍 in the style guide's buttons. Screenshots are kept to
/// compare with the approved design.
@MainActor
final class LoadingUITests: XCTestCase {
    /// Slow CI simulators can take many seconds to show a screen; a real failure still fails.
    private static let wait: TimeInterval = 30

    func testThePageJogs() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-loading",
        ]
        app.launch()
        let loader = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "加载中")).firstMatch
        XCTAssertTrue(loader.waitForExistence(timeout: Self.wait), "the launch page never showed its loader")
        Thread.sleep(forTimeInterval: 0.8)
        keepScreenshot(named: "90-loading-page")
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
