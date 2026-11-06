import XCTest

/// 通知 on the sample squad: the bell on 动态 has its dot, opening it lists everything the member
/// was told under 今天, 本周 and 更早 and takes the dot away, a row goes where it points, and with
/// nothing told the member's character stands there alone. Screenshots are kept for review.
@MainActor
final class NoticeBellUITests: XCTestCase {
    private static let wait: TimeInterval = 30

    func testTheBellOpensEverythingTold() {
        continueAfterFailure = false
        let app = launch(language: "zh-Hans")
        let bell = app.buttons["notices.bell"]
        XCTAssertTrue(bell.waitForExistence(timeout: Self.wait), "no bell on 动态")
        waitFor(bell, "value == '有新通知'", "the bell has no dot for the sample's new notices")
        assertOnScreen(bell, in: app)
        XCTAssertLessThan(
            bell.frame.maxY, app.staticTexts["feed.title"].frame.maxY + 8, "the bell isn't beside the title")
        settle()
        keepScreenshot(named: "100-notices-bell")

        bell.tap()
        let comment = app.buttons["notices.row.8"]
        XCTAssertTrue(comment.waitForExistence(timeout: Self.wait), "通知 didn't open")
        XCTAssertTrue(comment.label.contains("Coco 评论了你：这组深蹲太稳了"), "the comment row says \(comment.label)")
        let moved = app.buttons["notices.row.7"]
        XCTAssertTrue(moved.label.contains("阿杰 把小队搬到了跑道"), "the scene row says \(moved.label)")
        XCTAssertTrue(app.buttons["notices.row.6"].label.contains("教练 毛头 回复了你的打卡"))
        // The 6pm push: the squad's week on top, who patted under it, as the approved design shows.
        let daily = app.buttons["notices.row.5"].label
        XCTAssertTrue(daily.hasPrefix("本周小队已练 9/16 天"), "the 6pm row says \(daily)")
        XCTAssertTrue(daily.contains("Coco和另外 2 人拍了拍你"), "the 6pm row says \(daily)")
        let feedTab = app.buttons["tab.feed"]
        waitFor(feedTab, "exists == false OR hittable == false", "the tab bar stayed over 通知")
        for id in 1...9 {
            let row = app.buttons["notices.row.\(id)"]
            if row.exists, row.frame.maxY < app.windows.firstMatch.frame.maxY {
                assertOnScreen(row, in: app)
            }
        }
        settle()
        keepScreenshot(named: "101-notices")

        // A store's row says how it opened, in the home banner's words, from the member's unlock.
        let store = app.buttons["notices.row.3"]
        if !store.exists { app.swipeUp() }
        XCTAssertTrue(store.waitForExistence(timeout: Self.wait), "no store row")
        XCTAssertTrue(store.label.contains("DEUCE CLUB 开门了"), "the store row says \(store.label)")
        XCTAssertTrue(store.label.contains("网球练满 3 次"), "the store row says \(store.label)")
        app.swipeDown()

        // Back on 动态, everything is read: the dot is gone.
        app.buttons["notices.back"].tap()
        waitFor(bell, "value != '有新通知'", "the bell kept its dot after 通知 was opened")
        XCTAssertTrue(tabButton("tab.feed", in: app).waitForExistence(timeout: Self.wait))

        // The scene move goes home.
        bell.tap()
        XCTAssertTrue(moved.waitForExistence(timeout: Self.wait))
        moved.tap()
        XCTAssertTrue(
            tabButton("tab.today", in: app).waitForExistence(timeout: Self.wait), "the scene row didn't go home")
        waitFor(tabButton("tab.today", in: app), "selected == true", "the scene row didn't open 今天")
    }

    /// The coach's morning note's row opens it again on 今天, where 收下 puts it away.
    func testTheNoteRowShowsTheNoteAgain() {
        continueAfterFailure = false
        let app = launch(language: "zh-Hans")
        let bell = app.buttons["notices.bell"]
        XCTAssertTrue(bell.waitForExistence(timeout: Self.wait), "no bell on 动态")
        bell.tap()
        let note = app.buttons["notices.row.9"]
        XCTAssertTrue(note.waitForExistence(timeout: Self.wait), "通知 didn't open on its newest row")
        XCTAssertTrue(note.label.contains("毛头：今天出赛表写的是力量"), "the note row says \(note.label)")
        note.tap()
        let putAway = app.buttons["today.coachNote.putAway"]
        XCTAssertTrue(putAway.waitForExistence(timeout: Self.wait), "the note row didn't show the note on 今天")
        assertOnScreen(putAway, in: app)
        putAway.tap()
        waitFor(putAway, "exists == false", "收下 didn't put the note away")
    }

    func testNothingToldYet() {
        continueAfterFailure = false
        let app = launch(language: "zh-Hans", extra: ["-uitest-no-notices"])
        let bell = app.buttons["notices.bell"]
        XCTAssertTrue(bell.waitForExistence(timeout: Self.wait), "no bell on 动态")
        bell.tap()
        let empty = app.descendants(matching: .any).matching(identifier: "notices.empty").firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: Self.wait), "通知 didn't show its empty state")
        XCTAssertTrue(app.staticTexts["还没有通知"].exists)
        assertOnScreen(empty, in: app)
        settle()
        keepScreenshot(named: "102-notices-empty")
    }

    func testEnglishRowsStayOnScreen() {
        continueAfterFailure = false
        let app = launch(language: "en")
        let bell = app.buttons["notices.bell"]
        XCTAssertTrue(bell.waitForExistence(timeout: Self.wait), "no bell on 动态")
        bell.tap()
        let moved = app.buttons["notices.row.7"]
        XCTAssertTrue(moved.waitForExistence(timeout: Self.wait), "通知 didn't open")
        XCTAssertTrue(moved.label.contains("moved the squad to"), "the scene row says \(moved.label)")
        for id in 1...9 {
            let row = app.buttons["notices.row.\(id)"]
            if row.exists, row.frame.maxY < app.windows.firstMatch.frame.maxY {
                assertOnScreen(row, in: app)
            }
        }
        settle()
        keepScreenshot(named: "103-notices-en")
    }

    private func launch(language: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments +=
            [
                "-AppleLanguages", "(\(language))", "-AppleLocale", language, "-uitest-no-push", "-uitest-noon",
                // The sample member has opened DEUCE CLUB, as the sample's store notice says.
                "-uitest-unlocked", "-tab", "feed",
            ] + extra
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        return app
    }

    private func assertOnScreen(_ element: XCUIElement, in app: XCUIApplication) {
        let screen = app.windows.firstMatch.frame
        XCTAssertTrue(screen.contains(element.frame), "\(element.identifier) is cut off: \(element.frame)")
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
