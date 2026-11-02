import XCTest

/// Photos full screen while writing a post, the way a person checks them before posting. Photos
/// come from `-uitest-photos`, since UI tests can't drive the system photo picker reliably.
/// 动态's photos are checked in `FeedUITests`.
@MainActor
final class ComposePhotoUITests: XCTestCase {
    private static let wait: TimeInterval = 30

    /// Tapping the cover while writing a post shows the photos whole, full screen: swipe to the
    /// next, close, and the post is still being written.
    func testComposePhotoViewer() {
        let app = launch()
        let checkIn = app.buttons["today.checkin"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: Self.wait), "no 打卡 button")
        checkIn.tap()
        let trained = app.buttons["today.capsule.trained"]
        XCTAssertTrue(trained.waitForExistence(timeout: Self.wait), "no 练了 capsule")
        trained.tap()
        let post = app.buttons["compose.post"]
        XCTAssertTrue(post.waitForExistence(timeout: Self.wait), "the compose page never opened")

        app.descendants(matching: .any).matching(identifier: "compose.cover").firstMatch.tap()
        let viewer = app.descendants(matching: .any).matching(identifier: "photoViewer").firstMatch
        XCTAssertTrue(viewer.waitForExistence(timeout: Self.wait), "tapping the cover didn't open it full screen")
        let close = app.buttons["photoViewer.close"]
        XCTAssertTrue(close.waitForExistence(timeout: Self.wait), "no 关闭")
        XCTAssertTrue(app.windows.firstMatch.frame.contains(close.frame), "关闭 is cut off: \(close.frame)")
        settle()
        keepScreenshot(named: "15-compose-photo-viewer")
        viewer.swipeLeft()
        settle()
        keepScreenshot(named: "15-compose-photo-viewer-second")

        close.tap()
        XCTAssertTrue(viewer.waitForNonExistence(timeout: Self.wait), "关闭 didn't close the photos")
        XCTAssertTrue(post.isHittable, "the compose page didn't come back")
    }

    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-uitest-photos", "3", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push",
            "-uitest-noon", "-today.cardPage", "0",
        ]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        return app
    }

    /// Lets springs settle before a screenshot.
    private func settle() {
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
