import XCTest

/// Plans the week on 出赛表 the way a person does, and keeps screenshots for review. The clock
/// starts on this week's Thursday (`-uitest-thursday`), so Monday to Thursday are behind and
/// Friday to Sunday still to come; the in-memory member plans run, tennis, rest, strength, run,
/// rest, tennis this week.
@MainActor
final class ScheduleUITests: XCTestCase {
    private func launch(_ language: String = "zh-Hans") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(\(language))", "-AppleLocale", language, "-uitest-no-push", "-tab", "schedule",
            "-uitest-thursday", "-uitest-save-poster",
        ]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        XCTAssertTrue(app.buttons["schedule.lane.0"].waitForExistence(timeout: 30), "the poster never showed")
        return app
    }

    func testThisWeekMovesOnlyDaysStillToCome() {
        let app = launch()
        let tabBar = app.buttons["tab.schedule"]
        XCTAssertTrue(tabBar.isSelected)
        // The poster and the counts under it sit clear of the tab bar.
        let poster = find(app, "schedule.poster")
        XCTAssertLessThanOrEqual(poster.frame.maxY, tabBar.frame.minY, "the poster runs under the tab bar")
        XCTAssertGreaterThanOrEqual(poster.frame.minX, 0)
        XCTAssertLessThanOrEqual(poster.frame.maxX, app.frame.maxX)
        let squad = find(app, "schedule.count.squad")
        XCTAssertTrue(squad.waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(squad.frame.maxY, tabBar.frame.minY, "the counts sit under the tab bar")
        XCTAssertTrue(lane(app, 3).label.hasPrefix("今天"), "Thursday isn't today: \(lane(app, 3).label)")
        settle()
        keepScreenshot(named: "60-schedule-this-week")

        // Today and the days before it stay as they are.
        XCTAssertFalse(lane(app, 1).isEnabled, "Tuesday can still change")
        XCTAssertFalse(lane(app, 3).isEnabled, "today can still change")

        // A training day still to come takes another sport, never 休息.
        lane(app, 4).tap()
        let more = app.buttons["schedule.pick.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 10), "Friday's picks didn't open")
        XCTAssertFalse(app.buttons["schedule.pick.rest"].exists, "this week offers 休息")
        XCTAssertLessThanOrEqual(more.frame.maxY, tabBar.frame.minY, "the picks open under the tab bar")
        settle()
        keepScreenshot(named: "61-schedule-pick-a-sport")
        app.buttons["schedule.pick.yoga"].tap()
        waitFor(lane(app, 4), "label CONTAINS '瑜伽'", "Friday didn't turn to yoga")

        // A rest day lifts, then swaps with a training day.
        lane(app, 5).tap()
        waitFor(lane(app, 5), "isSelected == true", "Saturday didn't lift")
        settle()
        keepScreenshot(named: "62-schedule-lift-a-rest-day")
        lane(app, 6).tap()
        waitFor(lane(app, 6), "label CONTAINS '休息'", "Sunday didn't take the rest day")
        XCTAssertTrue(lane(app, 5).label.contains("网球"), "Saturday didn't take Sunday's tennis: \(lane(app, 5).label)")
        XCTAssertTrue(find(app, "schedule.tally").label.contains("5"), "the week's count changed")
    }

    func testNextWeekChangesFreelyWithFoodGoals() {
        let app = launch()
        let tabBar = app.buttons["tab.schedule"]
        // The bar opens on 本周 with 下周 beside it, in view and tappable.
        let nextWeek = app.buttons["下周"]
        waitFor(nextWeek, "hittable == true", "下周 isn't in view", timeout: 10)
        XCTAssertLessThanOrEqual(
            nextWeek.frame.maxX, app.buttons["schedule.save"].frame.minX, "下周 is hidden under 存图")
        nextWeek.tap()
        waitFor(nextWeek, "isSelected == true", "下周 didn't open", timeout: 10)
        let countdown = find(app, "schedule.countdown")
        XCTAssertTrue(countdown.waitForExistence(timeout: 10), "no countdown on next week")
        XCTAssertLessThanOrEqual(countdown.frame.maxY, tabBar.frame.minY, "the countdown sits under the tab bar")
        settle()
        keepScreenshot(named: "63-schedule-next-week")

        // Any day becomes a rest day.
        lane(app, 0).tap()
        let rest = app.buttons["schedule.pick.rest"]
        XCTAssertTrue(rest.waitForExistence(timeout: 10), "next week offers no 休息")
        rest.tap()
        waitFor(lane(app, 0), "label CONTAINS '休息'", "Monday didn't turn to rest")
        XCTAssertTrue(find(app, "schedule.tally").label.contains("4"), "the plan's count didn't change")
        settle()
        keepScreenshot(named: "64-schedule-next-week-rest")
        lane(app, 0).tap()

        // 饮食小目标: up to three, from the list or written.
        app.buttons["schedule.fuel"].tap()
        let own = app.buttons["schedule.fuel.own"]
        XCTAssertTrue(own.waitForExistence(timeout: 10), "the food goals didn't open")
        XCTAssertLessThanOrEqual(own.frame.maxY, tabBar.frame.minY, "the food goals open under the tab bar")
        app.buttons["schedule.fuel.每天有菜"].tap()
        settle()
        keepScreenshot(named: "65-schedule-food-goals")
        own.tap()
        let field = app.textFields["schedule.fuel.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no field for my own goal")
        field.typeText("少喝咖啡")
        let add = app.buttons["schedule.fuel.add"]
        XCTAssertTrue(add.isHittable, "加上 is covered by the keyboard")
        settle()
        keepScreenshot(named: "66-schedule-own-food-goal")
        add.tap()
        waitFor(app.buttons["schedule.fuel"], "label CONTAINS '少喝咖啡'", "my goal isn't on the poster")
        XCTAssertFalse(app.buttons["schedule.fuel.own"].isEnabled, "a fourth goal can still be added")
    }

    func testPastWeekShowsItsTitlesAndSaves() {
        let app = launch()
        // Last week: the chip just before 本周.
        let thisWeek = app.buttons["本周"]
        XCTAssertTrue(thisWeek.waitForExistence(timeout: 10))
        let chips = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'schedule.week.'"))
        let labels = chips.allElementsBoundByIndex.map(\.label)
        guard let index = labels.firstIndex(of: thisWeek.label), index > 0 else {
            return XCTFail("no week before this one: \(labels)")
        }
        chips.element(boundBy: index - 1).tap()

        XCTAssertFalse(lane(app, 4).isEnabled, "a past week can change")
        XCTAssertTrue(find(app, "schedule.title.0").waitForExistence(timeout: 10), "last week has no title")
        // The 颁奖词 sit under the poster, clear of the lanes, in place of the counts.
        let award = find(app, "schedule.award.0")
        XCTAssertTrue(award.waitForExistence(timeout: 10), "the award has no card under the poster")
        XCTAssertGreaterThanOrEqual(
            award.frame.minY, find(app, "schedule.poster").frame.maxY, "the award covers the poster")
        XCTAssertFalse(find(app, "schedule.count.squad").exists, "a past week still shows its counts")
        settle()
        keepScreenshot(named: "67-schedule-past-week-award")
        // Scrolled up, the 颁奖词 read whole above the tab bar, and the weeks and 存图 stay put
        // rather than sliding under the status bar.
        let saveTop = app.buttons["schedule.save"].frame.minY
        app.swipeUp()
        settle()
        XCTAssertEqual(app.buttons["schedule.save"].frame.minY, saveTop, accuracy: 1, "the top bar scrolled away")
        XCTAssertLessThanOrEqual(
            award.frame.maxY, app.buttons["tab.schedule"].frame.minY, "the award sits under the tab bar")
        keepScreenshot(named: "67-schedule-past-week-award-words")
        app.swipeDown()
        settle()

        app.buttons["schedule.save"].tap()
        XCTAssertTrue(find(app, "schedule.saved").waitForExistence(timeout: 10), "存图 didn't say it saved")
        keepScreenshot(named: "68-schedule-saved")
    }

    func testEnglish() {
        let app = launch("en")
        XCTAssertTrue(app.buttons["Next week"].exists)
        XCTAssertTrue(lane(app, 3).label.hasPrefix("Today"), lane(app, 3).label)
        settle()
        keepScreenshot(named: "69-schedule-english")
    }

    /// Any element by identifier: grouped views can surface as text or as other elements.
    private func find(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func lane(_ app: XCUIApplication, _ index: Int) -> XCUIElement {
        app.buttons["schedule.lane.\(index)"]
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
