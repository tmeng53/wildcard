import XCTest

/// Posting a 训练 from Apple Health on the sample day (`-health-sample`: a ride a minute ago,
/// yoga, a swim, strength and a run), the way a member does: the home's card, 发一条, the chips
/// and the 成绩条 on the compose page, a number struck out, the post on 动态; and 设置 › Apple 健康.
/// Screenshots go beside the approved boards (T1–T8, U1–U9).
@MainActor
final class HealthUITests: XCTestCase {
    private static let wait: TimeInterval = 30

    /// The card under the squad card offers the newest workout; 发一条 opens the 训练 filled from
    /// it, its map first in the row. Picking another chip switches, tapping it again lets it go
    /// and the minutes come back; a struck number stays off the post.
    func testPostFromTheHomeCard() {
        let app = launch()
        let card = app.descendants(matching: .any).matching(identifier: "today.health").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: Self.wait), "no Apple Health card on 今天")
        assertOnScreen(card, in: app)
        settle()
        keepScreenshot(named: "70-health-home-card")

        app.buttons["today.health.post"].tap()
        let score = app.descendants(matching: .any).matching(identifier: "compose.score").firstMatch
        XCTAssertTrue(score.waitForExistence(timeout: Self.wait), "发一条 didn't open the 训练 with its 成绩条")
        let map = app.buttons["compose.workoutTile"]
        XCTAssertTrue(map.exists, "the ride's map isn't in the photo row")
        XCTAssertFalse(app.buttons["compose.minutes.45"].exists, "the minutes show beside the 成绩条")
        settle()
        keepScreenshot(named: "71-health-compose-ride")

        // The swim: its laps chart takes the map's place.
        app.buttons["compose.health.sample-swim"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "strip.laps").firstMatch
                .waitForExistence(timeout: Self.wait), "the swim's 趟数 isn't on the 成绩条")
        settle()
        keepScreenshot(named: "72-health-compose-swim")

        // Tapped again, it lets go: the minutes come back.
        app.buttons["compose.health.sample-swim"].tap()
        XCTAssertTrue(
            app.buttons["compose.minutes.45"].waitForExistence(timeout: Self.wait),
            "letting go didn't bring the minutes back")
        XCTAssertFalse(map.exists, "the tile stayed after letting go")

        // The run, with its heart rate struck out, posts.
        app.buttons["compose.health.sample-run"].tap()
        let heart = app.buttons["strip.averageHeartRate"]
        XCTAssertTrue(heart.waitForExistence(timeout: Self.wait), "the run has no 平均心率")
        heart.tap()
        XCTAssertEqual(heart.value as? String, "不发", "tapping didn't strike 平均心率 out")
        settle()
        keepScreenshot(named: "73-health-compose-struck")
        app.buttons["compose.post"].tap()
        XCTAssertTrue(score.waitForNonExistence(timeout: Self.wait), "the post didn't go out")
    }

    /// 设置 › Apple 健康: connected, the switches for what a post carries, and where iOS keeps
    /// the reading permission.
    func testSettingsPage() {
        let app = launch(extra: ["-tab", "me"])
        let settings = app.buttons["me.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: Self.wait), "no 设置 on 我")
        settings.tap()
        let row = app.buttons["me.health"]
        XCTAssertTrue(row.waitForExistence(timeout: Self.wait), "no Apple 健康 in 设置")
        row.tap()
        let page = app.descendants(matching: .any).matching(identifier: "health.page").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: Self.wait), "Apple 健康 didn't open")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "health.share.route").firstMatch.exists,
            "no 路线地图 switch")
        settle()
        keepScreenshot(named: "74-health-settings")
        let permissions = app.buttons["health.permissions"]
        assertOnScreen(permissions, in: app)
    }

    private func launch(extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments +=
            [
                "-health-sample", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push",
                "-uitest-noon", "-today.cardPage", "0",
            ] + extra
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        return app
    }

    /// Fully inside the window.
    private func assertOnScreen(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.exists, "\(element) isn't there")
        XCTAssertTrue(
            app.windows.firstMatch.frame.contains(element.frame), "\(element) is cut off: \(element.frame)")
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
