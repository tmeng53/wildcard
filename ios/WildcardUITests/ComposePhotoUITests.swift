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
        XCTAssertTrue(trained.waitForExistence(timeout: Self.wait), "no 训练 capsule")
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

    /// Three photos fill the row, so there is no 「+ 照片」 until × takes one off. With something
    /// added, 取消 asks 「放弃这条动态？」: 继续编辑 stays, 放弃 leaves.
    func testRemovePhotoAndDiscard() {
        let app = launch()
        app.buttons["today.checkin"].tap()
        let meal = app.buttons["today.capsule.healthyMeal"]
        XCTAssertTrue(meal.waitForExistence(timeout: Self.wait), "no 健康餐 capsule")
        meal.tap()
        let add = app.buttons["compose.addPhoto"]
        let caption = app.descendants(matching: .any).matching(identifier: "compose.caption").firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: Self.wait), "the compose page never opened")
        XCTAssertFalse(add.exists, "「+ 照片」 shows with three photos")

        app.buttons["compose.photo.3.remove"].tap()
        XCTAssertTrue(add.waitForExistence(timeout: Self.wait), "× didn't make room for 「+ 照片」")
        XCTAssertFalse(app.buttons["compose.photo.3"].exists, "× didn't take the photo off")
        app.buttons["compose.photo.2"].tap()
        XCTAssertEqual(app.buttons["compose.photo.2"].label, "第 2 张照片", "the old cover didn't move along")
        settle()
        keepScreenshot(named: "15-compose-two-photos")

        app.buttons["compose.cancel"].tap()
        XCTAssertTrue(
            app.staticTexts["放弃这条动态？"].waitForExistence(timeout: Self.wait), "取消 didn't ask before discarding")
        settle()
        keepScreenshot(named: "15-compose-discard")
        // iOS 26 lists an alert's button twice (a Button inside a PopUpButton).
        app.buttons["compose.keepEditing"].firstMatch.tap()
        XCTAssertTrue(caption.waitForExistence(timeout: Self.wait), "继续编辑 left the compose page")
        app.buttons["compose.cancel"].tap()
        let discard = app.buttons["compose.discard"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: Self.wait), "取消 didn't ask again")
        discard.tap()
        XCTAssertTrue(caption.waitForNonExistence(timeout: Self.wait), "放弃 didn't close the compose page")
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
