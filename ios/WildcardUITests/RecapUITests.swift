import XCTest

/// Opens the 战报 from its tile and walks every page of the sample week, keeping a screenshot
/// of each once its animation has played. CI uploads them (scripts/ios-test.sh).
@MainActor
final class RecapUITests: XCTestCase {
    /// A busy CI simulator can take seconds per accessibility query.
    private static let wait: TimeInterval = 30

    func testReadyStoryInChinese() {
        let app = launch(language: "zh-Hans")
        let tile = app.buttons["recap.entry"]
        XCTAssertTrue(tile.waitForExistence(timeout: Self.wait), "no 战报 tile")
        XCTAssertTrue(tile.label.contains("每周战报"))
        keepScreenshot(named: "70-recap-tile")
        tile.tap()

        let pages = [
            ("podium", 4.0), ("titles", 2.5), ("myWeek", 1.5), ("squadWeek", 1.5), ("favoritePlace", 3.0),
            ("discovery", 3.0), ("hottest", 2.5), ("meals", 3.0), ("menu", 1.5), ("bestDisclaimer", 3.5),
            ("ending", 3.0),
        ]
        for (index, (page, settle)) in pages.enumerated() {
            show(page, in: app)
            // Let the page's animation play out before the shot.
            Thread.sleep(forTimeInterval: settle)
            keepScreenshot(named: "7\(String(format: "%02d", index + 1))-recap-\(page)")
            if page != "ending" { next(in: app, from: page) }
        }
        let save = app.buttons["recap.save"]
        XCTAssertTrue(save.waitForExistence(timeout: Self.wait), "no 存图 on the ending")
        XCTAssertTrue(save.isEnabled, "存图 never got its picture")
        XCTAssertTrue(app.buttons["recap.planNextWeek"].exists)
        app.buttons["recap.close"].tap()
        XCTAssertTrue(tile.waitForExistence(timeout: Self.wait), "✕ didn't close the story")
    }

    /// 排下周 on the last page closes the story and opens 出赛表 in 我: in the app on the sample
    /// squad, from 动态's tile, since `-recap`'s plain page has no 出赛表 to open.
    func testPlanNextWeekOpensSchedule() {
        let app = launch(language: "zh-Hans", extra: ["-tab", "feed"], demo: false)
        let tile = app.buttons["recap.entry"]
        XCTAssertTrue(tile.waitForExistence(timeout: Self.wait), "no 战报 tile")
        tile.tap()
        for page in Self.pages {
            show(page, in: app)
            if page != "ending" { next(in: app, from: page) }
        }
        let plan = app.buttons["recap.planNextWeek"]
        XCTAssertTrue(plan.waitForExistence(timeout: Self.wait), "no 排下周 on the ending")
        plan.tap()
        XCTAssertTrue(app.buttons["schedule.save"].waitForExistence(timeout: Self.wait), "排下周 didn't open 出赛表")
        keepScreenshot(named: "7a-recap-plan-next-week")
    }

    /// 小队菜单's card turns over to its stars and place, whose 地点页 pushes over the story; back, the
    /// story is where it was. The heads on 小队最爱去 fan out, and its place opens too.
    func testMenuAndPlacesOpenTheirPlace() {
        let app = launch(language: "zh-Hans", extra: ["-tab", "feed"], demo: false)
        let tile = app.buttons["recap.entry"]
        XCTAssertTrue(tile.waitForExistence(timeout: Self.wait), "no 战报 tile")
        tile.tap()
        for page in Self.pages.prefix(while: { $0 != "favoritePlace" }) {
            show(page, in: app)
            next(in: app)
        }
        show("favoritePlace", in: app)
        let heads = app.buttons["recap.place.heads"]
        XCTAssertTrue(heads.waitForExistence(timeout: Self.wait), "no heads on 小队最爱去")
        Thread.sleep(forTimeInterval: 2.5)
        heads.tap()
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot(named: "7l-recap-favorite-fanned")
        app.buttons["recap.place.open"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["place.page"].waitForExistence(timeout: Self.wait),
            "the place's name didn't open 地点页")
        keepScreenshot(named: "7m-recap-favorite-place-page")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["place.page"].waitForNonExistence(timeout: Self.wait),
            "back didn't leave 地点页")
        show("favoritePlace", in: app)

        for page in ["favoritePlace", "discovery", "hottest", "meals"] {
            show(page, in: app)
            next(in: app)
        }
        show("menu", in: app)
        let card = app.descendants(matching: .any)["recap.menu.0"]
        XCTAssertTrue(card.waitForExistence(timeout: Self.wait), "no dish on 小队菜单")
        Thread.sleep(forTimeInterval: 1)
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        let place = app.buttons["recap.menu.place"]
        XCTAssertTrue(place.waitForExistence(timeout: Self.wait), "the dish didn't turn over to its place")
        keepScreenshot(named: "7n-recap-menu-back")
        place.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["place.page"].waitForExistence(timeout: Self.wait),
            "the dish's place didn't open 地点页")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["place.page"].waitForNonExistence(timeout: Self.wait),
            "back didn't leave 地点页")
        show("menu", in: app)
        // Back from a place, a tap still moves the story on.
        next(in: app, from: "menu")
        show("bestDisclaimer", in: app)
    }

    /// Every page of the sample week, in order.
    private static let pages = [
        "podium", "titles", "myWeek", "squadWeek", "favoritePlace", "discovery", "hottest", "meals", "menu",
        "bestDisclaimer", "ending",
    ]

    /// Only the titles wait while the AI run is late: the out-of-funds page and its nudge.
    func testPendingTitlesCanBeNudged() {
        let app = launch(language: "zh-Hans", extra: ["-recap-pending"])
        app.buttons["recap.entry"].tap()
        show("podium", in: app)
        next(in: app)
        show("pending", in: app)
        Thread.sleep(forTimeInterval: 1.5)
        keepScreenshot(named: "78-recap-pending")
        let nudge = app.buttons["recap.nudge"]
        XCTAssertTrue(nudge.waitForExistence(timeout: Self.wait), "no 催一下主办方")
        nudge.tap()
        XCTAssertTrue(app.staticTexts["已经催过了，颁奖一会儿就到"].waitForExistence(timeout: Self.wait), "the nudge didn't land")
        keepScreenshot(named: "79-recap-pending-nudged")
        next(in: app)
        show("myWeek", in: app)
    }

    /// Before the AI run reaches the squad, the titles are only on their way: no organizers, no
    /// nudge.
    func testWaitingTitlesHaveNoNudge() {
        let app = launch(language: "zh-Hans", extra: ["-recap-waiting"])
        app.buttons["recap.entry"].tap()
        show("podium", in: app)
        next(in: app)
        show("pending", in: app)
        XCTAssertTrue(
            app.staticTexts["颁奖嘉宾在路上，一会儿就到"].waitForExistence(timeout: Self.wait), "no on-their-way line")
        XCTAssertFalse(app.buttons["recap.nudge"].exists, "a nudge while nothing failed")
        Thread.sleep(forTimeInterval: 1.5)
        keepScreenshot(named: "78-recap-pending-waiting")
        next(in: app)
        show("myWeek", in: app)
    }

    func testMissedEndingInEnglish() {
        let app = launch(language: "en", extra: ["-recap-missed"])
        let tile = app.buttons["recap.entry"]
        XCTAssertTrue(tile.waitForExistence(timeout: Self.wait), "no recap tile")
        XCTAssertTrue(tile.label.contains("Weekly recap"))
        tile.tap()
        for page in Self.pages.dropLast() {
            show(page, in: app)
            next(in: app, from: page)
        }
        show("ending", in: app)
        Thread.sleep(forTimeInterval: 3)
        keepScreenshot(named: "80-recap-ending-missed-en")
        XCTAssertEqual(app.buttons["recap.planNextWeek"].label, "Plan next week")
    }

    /// 动态 shows the squad's newest 战报 as its tile, clear of the tab bar, and the tile opens it;
    /// once watched to the end the tile goes, the story staying on 小队's 往期战报.
    func testFeedTileOpensTheStory() {
        let app = launch(language: "zh-Hans", extra: ["-tab", "feed"], demo: false)
        let tile = app.buttons["recap.entry"]
        XCTAssertTrue(tile.waitForExistence(timeout: Self.wait), "动态 shows no 战报 tile")
        let bar = tabButton("tab.feed", in: app)
        XCTAssertTrue(bar.isSelected, "-tab feed didn't open on 动态")
        XCTAssertLessThan(tile.frame.maxY, bar.frame.minY, "the tile runs under the tab bar")
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot(named: "81-recap-feed-tile")
        tile.tap()
        show("podium", in: app)
        app.buttons["recap.close"].tap()
        XCTAssertTrue(tile.waitForExistence(timeout: Self.wait), "✕ didn't go back to 动态")

        tile.tap()
        let ending = app.descendants(matching: .any).matching(identifier: "recap.page.ending").firstMatch
        for _ in 0..<14 where !ending.exists {
            XCTAssertTrue(app.buttons["recap.close"].waitForExistence(timeout: Self.wait), "the story didn't open")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.9)).tap()
        }
        XCTAssertTrue(ending.waitForExistence(timeout: Self.wait), "the last page never showed")
        app.buttons["recap.close"].tap()
        XCTAssertTrue(tile.waitForNonExistence(timeout: Self.wait), "动态 still shows a 战报 watched to the end")
    }

    private func launch(language: String, extra: [String] = [], demo: Bool = true) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", language]
        app.launchArguments += (demo ? ["-recap"] : []) + ["-uitest-recap-manual", "-uitest-no-push"] + extra
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        return app
    }

    private func show(_ page: String, in app: XCUIApplication) {
        let element = app.descendants(matching: .any).matching(identifier: "recap.page.\(page)").firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: Self.wait), "the \(page) page never showed")
    }

    /// A tap on the right of the screen, as a reader moves on; on 小队菜单, low down, under its cards,
    /// which a tap turns over.
    private func next(in app: XCUIApplication, from page: String? = nil) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: page == "menu" ? 0.9 : 0.5)).tap()
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
