import XCTest

/// Posting a 训练 from Apple Health on the sample day (`-health-sample`: a ride a minute ago,
/// yoga, a swim, strength, a ski day and a run), the way a member does: the home's card, 打卡 and its ✕, the chips
/// and the 成绩条 on the compose page, a number struck out, the post on 动态; and 设置 › Apple 健康.
/// Screenshots go beside the approved boards (T1–T8, U1–U9).
@MainActor
final class HealthUITests: XCTestCase {
    private static let wait: TimeInterval = 30

    /// The card under the squad card offers the newest workout; 打卡 opens the 训练 filled from
    /// it, its map first in the row. Picking another chip switches, tapping it again lets it go
    /// and the minutes come back; a struck number stays off the post. Back home, the card's ✕
    /// puts its workout away and the card offers the one before.
    func testPostFromTheHomeCard() {
        let app = launch()
        let card = app.descendants(matching: .any).matching(identifier: "today.health").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: Self.wait), "no Apple Health card on 今天")
        assertOnScreen(card, in: app)
        settle()
        keepScreenshot(named: "70-health-home-card")

        app.buttons["today.health.post"].tap()
        let score = app.descendants(matching: .any).matching(identifier: "compose.score").firstMatch
        XCTAssertTrue(score.waitForExistence(timeout: Self.wait), "打卡 didn't open the 训练 with its 成绩条")
        let map = app.buttons["compose.workoutTile"]
        let chart = app.buttons["compose.chartTile"]
        XCTAssertTrue(map.exists, "the ride's map isn't in the photo row")
        XCTAssertTrue(chart.exists, "the ride's heart rate isn't beside its map")
        XCTAssertFalse(app.buttons["compose.minutes.60"].exists, "the minutes show beside the 成绩条")
        keepTheRideAndOpenItsChart(chart, in: app)

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
            app.buttons["compose.minutes.60"].waitForExistence(timeout: Self.wait),
            "letting go didn't bring the minutes back")
        XCTAssertFalse(chart.exists, "the tile stayed after letting go")

        // The yoga's heart-rate chart goes when its 平均心率 is struck, and comes back with it.
        app.buttons["compose.health.sample-yoga"].tap()
        let yogaHeart = app.buttons["strip.averageHeartRate"]
        XCTAssertTrue(yogaHeart.waitForExistence(timeout: Self.wait), "the yoga has no 平均心率")
        XCTAssertTrue(chart.exists, "the yoga's chart isn't in the photo row")
        XCTAssertFalse(map.exists, "the yoga has a map")
        tapClearOfTheFeedSwitch(yogaHeart, in: app)
        XCTAssertTrue(chart.waitForNonExistence(timeout: Self.wait), "striking 平均心率 left the chart")
        tapClearOfTheFeedSwitch(yogaHeart, in: app)
        XCTAssertTrue(chart.waitForExistence(timeout: Self.wait), "restoring 平均心率 didn't bring the chart back")

        checkTheSkiDay(in: app)

        // The run, with its heart rate struck out, posts its map alone.
        app.buttons["compose.health.sample-run"].tap()
        let heart = app.buttons["strip.averageHeartRate"]
        XCTAssertTrue(heart.waitForExistence(timeout: Self.wait), "the run has no 平均心率")
        tapClearOfTheFeedSwitch(heart, in: app)
        XCTAssertEqual(heart.value as? String, "不发", "tapping didn't strike 平均心率 out")
        XCTAssertTrue(chart.waitForNonExistence(timeout: Self.wait), "the run's heart rate stayed when struck")
        XCTAssertTrue(map.exists, "striking 平均心率 took the run's map off")
        strikeTheDuration(in: app)
        settle()
        keepScreenshot(named: "73-health-compose-struck")
        app.buttons["compose.post"].tap()
        XCTAssertTrue(score.waitForNonExistence(timeout: Self.wait), "the post didn't go out")
        putAwayFromTheCard(in: app)
    }

    /// The ride on the compose page; tapping its chart opens it full screen, as a photo does, and
    /// 关闭 puts it back in the row.
    private func keepTheRideAndOpenItsChart(_ chart: XCUIElement, in app: XCUIApplication) {
        settle()
        keepScreenshot(named: "71-health-compose-ride")
        chart.tap()
        let bigChart = app.descendants(matching: .any).matching(identifier: "compose.viewer.chart").firstMatch
        XCTAssertTrue(bigChart.waitForExistence(timeout: Self.wait), "tapping the chart didn't open it full screen")
        settle()
        assertOnScreen(bigChart, in: app)
        keepScreenshot(named: "71b-health-compose-chart-full")
        app.buttons["photoViewer.close"].tap()
        XCTAssertTrue(bigChart.waitForNonExistence(timeout: Self.wait), "关闭 didn't close the chart")
    }

    /// 时长 is struck like any other number (Tracy, 2026-11-08).
    private func strikeTheDuration(in app: XCUIApplication) {
        let duration = app.buttons["strip.duration"]
        tapClearOfTheFeedSwitch(duration, in: app)
        XCTAssertEqual(duration.value as? String, "不发", "tapping didn't strike 时长 out")
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

        // Scrolled to the end, the last line clears the tab bar.
        page.swipeUp()
        page.swipeUp()
        settle()
        let hint = app.staticTexts["health.permissions.hint"]
        assertOnScreen(hint, in: app)
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists {
            XCTAssertLessThanOrEqual(
                hint.frame.maxY, tabBar.frame.minY, "the last line is behind the tab bar: \(hint.frame)")
        }
        keepScreenshot(named: "75-health-settings-bottom")
    }

    /// The ski day: 趟数 · 落差 · 最高速 in place of heart rate on its 成绩条.
    private func checkTheSkiDay(in app: XCUIApplication) {
        app.buttons["compose.health.sample-ski"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "strip.runs").firstMatch
                .waitForExistence(timeout: Self.wait), "the ski day's 趟数 isn't on the 成绩条")
        for cell in ["strip.descent", "strip.topSpeed"] {
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: cell).firstMatch.exists, "no \(cell)")
        }
        XCTAssertFalse(app.buttons["strip.averageHeartRate"].exists, "the ski day's 成绩条 shows heart rate")
        settle()
        keepScreenshot(named: "75-health-compose-ski")
    }

    /// A home screen widget's 打卡 on a workout opens the app on the 训练 page started from it,
    /// as the home's card does, and posts nothing by itself: here the swim, not the newest, so the
    /// page follows the widget's workout. The app opens from cold with the widget's link, as a tap
    /// on the widget opens it, once the home and Health are read.
    func testWidgetCapsuleOpensThePrefilledTraining() {
        let app = launch(extra: [
            "-widget-link", "wildcard://widget/check-in?provider=apple_health&workout=sample-swim",
        ])
        let score = app.descendants(matching: .any).matching(identifier: "compose.score").firstMatch
        XCTAssertTrue(score.waitForExistence(timeout: Self.wait), "the widget's 打卡 didn't open the 训练 page")
        XCTAssertTrue(app.buttons["compose.health.sample-swim"].isSelected, "the page didn't start from the swim")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "strip.laps").firstMatch.exists,
            "the swim's laps aren't on the 成绩条")
        XCTAssertTrue(app.buttons["compose.post"].exists, "nothing to send it with")
        settle()
        keepScreenshot(named: "76-health-widget-compose")
    }

    /// Back home, the card's ✕ puts its workout away, and the card offers the next one instead.
    private func putAwayFromTheCard(in app: XCUIApplication) {
        let summary = app.descendants(matching: .any).matching(identifier: "today.health.summary").firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: Self.wait), "no Apple Health card after posting")
        let offered = summary.label
        app.buttons["today.health.dismiss"].tap()
        let next = NSPredicate(format: "label != %@", offered)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation(for: next, evaluatedWith: summary)], timeout: Self.wait), .completed,
            "the ✕ didn't put \(offered) away")
    }

    private func launch(extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments +=
            [
                "-health-sample", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push",
                "-uitest-noon", "-today.cardPage", "0",
            ] + extra
        // Home opens on the folded capsule, as these tests were written for.
        app.launchArguments.append("-uitest-card-folded")
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        return app
    }

    /// 发布到动态 floats over the compose page's foot, so a 成绩条 cell low on the page can sit
    /// under it (the ticket's 添加位置 row made the page taller): scroll the cell clear of it first.
    private func tapClearOfTheFeedSwitch(_ element: XCUIElement, in app: XCUIApplication) {
        let floating = app.descendants(matching: .any)["compose.inFeed"].firstMatch
        var swipes = 0
        while floating.exists, element.frame.maxY > floating.frame.minY - 12, swipes < 4 {
            app.scrollViews.firstMatch.swipeUp(velocity: .slow)
            swipes += 1
        }
        element.tap()
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
