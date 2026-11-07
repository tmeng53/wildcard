import XCTest

/// The tab bar over the signed-in app: every tab opens from it, and it steps aside while a
/// check-in is being written.
@MainActor
final class TabsUITests: XCTestCase {
    func testTabsSwitchAndStepAsideWhileComposing() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-photos", "1",
        ]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }

        let today = app.buttons["tab.today"]
        XCTAssertTrue(today.waitForExistence(timeout: 30), "no tab bar")
        XCTAssertTrue(today.isSelected, "the app didn't open on 今天")
        XCTAssertEqual(
            ["tab.today", "tab.feed", "tab.me"].map { app.buttons[$0].label },
            ["小队", "动态", "我"])
        XCTAssertFalse(app.buttons["tab.schedule"].exists, "出赛表 is still a tab")
        XCTAssertFalse(app.buttons["tab.squad"].exists, "小队 is still a tab")
        // 打卡 sits above the bar, not under it.
        let checkIn = app.buttons["today.checkin"]
        XCTAssertTrue(checkIn.isHittable, "打卡 is covered")
        XCTAssertLessThan(checkIn.frame.maxY, today.frame.minY, "打卡 overlaps the tab bar")
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot(named: "30-tabs-today")

        app.buttons["tab.feed"].tap()
        waitFor(app.buttons["tab.feed"], "isSelected == true", "动态 didn't open")
        XCTAssertTrue(app.staticTexts["feed.title"].waitForExistence(timeout: 30), "动态 shows another screen")
        XCTAssertFalse(checkIn.exists, "今天 still shows under 动态")
        app.buttons["tab.me"].tap()
        waitFor(app.buttons["tab.me"], "isSelected == true", "tab.me didn't open")
        let mePage = app.descendants(matching: .any).matching(identifier: "me.page").firstMatch
        XCTAssertTrue(mePage.waitForExistence(timeout: 30), "我 didn't show its page")
        XCTAssertFalse(checkIn.exists, "今天 still shows under tab.me")
        app.buttons["tab.today"].tap()
        waitFor(today, "isSelected == true", "今天 didn't open again")
        XCTAssertFalse(mePage.exists, "the last tab's screen stayed over 今天")

        // The 打卡 burst takes the screen: the bar steps aside until it closes.
        checkIn.tap()
        let meal = app.buttons["today.capsule.healthyMeal"]
        XCTAssertTrue(meal.waitForExistence(timeout: 30))
        waitFor(today, "exists == false", "the tab bar stayed over the open burst")
        meal.tap()
        XCTAssertTrue(app.buttons["compose.post"].waitForExistence(timeout: 30), "the compose page never opened")
        waitFor(today, "exists == false", "the tab bar stayed over the compose page")
    }

    /// The squad's name on home's card opens 小队 in 今天's place, with the tab bar under it, and
    /// 返回 goes back home.
    func testSquadCardOpensTheSquadPage() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-today.cardCollapsed", "0",
        ]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }

        let squadName = app.descendants(matching: .any)["squadcard.squad"]
        XCTAssertTrue(squadName.waitForExistence(timeout: 30), "home's card has no squad name")
        squadName.tap()
        let squadPage = app.descendants(matching: .any).matching(identifier: "squad.page").firstMatch
        XCTAssertTrue(squadPage.waitForExistence(timeout: 30), "the squad card didn't show 小队")
        XCTAssertTrue(app.buttons["tab.today"].isSelected, "小队 left 今天")
        backButton(in: app).tap()
        waitFor(squadPage, "exists == false", "返回 didn't close 小队")
        XCTAssertTrue(app.buttons["today.checkin"].waitForExistence(timeout: 30), "返回 didn't go back home")
    }

    /// `-tab` opens straight on another tab, as screenshots of later tabs need; `-tab schedule`
    /// opens 我 on 出赛表.
    func testLaunchOnAnotherTab() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-tab", "schedule",
        ]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }

        // 出赛表 is pushed over 我, and the system's bar drops the tabs' identifiers at times while
        // a page is pushed, so the tab is found by its place.
        let meTab = tabButton("tab.me", in: app)
        XCTAssertTrue(meTab.isSelected, "-tab schedule didn't open on 我")
        XCTAssertTrue(app.buttons["schedule.save"].waitForExistence(timeout: 30), "-tab schedule didn't show 出赛表")
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
