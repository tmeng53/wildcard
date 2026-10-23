import XCTest

/// Opens the 战报 from its tile and walks every page of the sample week, keeping a screenshot
/// of each once its animation has played. CI uploads them (scripts/ios-test.sh).
@MainActor
final class RecapUITests: XCTestCase {
    /// A busy CI simulator can take seconds per accessibility query; see StyleGuideUITests.
    private static let wait: TimeInterval = 30

    func testReadyStoryInChinese() {
        let app = launch(language: "zh-Hans")
        let tile = app.buttons["recap.entry"]
        XCTAssertTrue(tile.waitForExistence(timeout: Self.wait), "no 战报 tile")
        XCTAssertTrue(tile.label.contains("本周战报"))
        keepScreenshot(named: "recap-00-tile")
        tile.tap()

        let pages = [
            ("podium", 4.0), ("titles", 2.5), ("myWeek", 11.0), ("hottest", 2.5), ("meals", 3.0),
            ("bestDisclaimer", 3.5), ("ending", 3.0),
        ]
        for (index, (page, settle)) in pages.enumerated() {
            show(page, in: app)
            // Let the page's animation play out before the shot.
            Thread.sleep(forTimeInterval: settle)
            keepScreenshot(named: "recap-\(String(format: "%02d", index + 1))-\(page)")
            if page != "ending" { next(in: app) }
        }
        XCTAssertTrue(app.buttons["recap.save"].waitForExistence(timeout: Self.wait), "no 存图 on the ending")
        XCTAssertTrue(app.buttons["recap.planNextWeek"].exists)
        app.buttons["recap.close"].tap()
        XCTAssertTrue(tile.waitForExistence(timeout: Self.wait), "✕ didn't close the story")
    }

    /// Only the titles wait while the AI run is late: the out-of-funds page and its nudge.
    func testPendingTitlesCanBeNudged() {
        let app = launch(language: "zh-Hans", extra: ["-recap-pending"])
        app.buttons["recap.entry"].tap()
        show("podium", in: app)
        next(in: app)
        show("pending", in: app)
        Thread.sleep(forTimeInterval: 1.5)
        keepScreenshot(named: "recap-10-pending")
        let nudge = app.buttons["recap.nudge"]
        XCTAssertTrue(nudge.waitForExistence(timeout: Self.wait), "no 催一下主办方")
        nudge.tap()
        XCTAssertTrue(app.staticTexts["已催主办方充值 token"].waitForExistence(timeout: Self.wait), "the nudge didn't land")
        keepScreenshot(named: "recap-11-pending-nudged")
        next(in: app)
        show("myWeek", in: app)
    }

    func testMissedEndingInEnglish() {
        let app = launch(language: "en", extra: ["-recap-missed"])
        let tile = app.buttons["recap.entry"]
        XCTAssertTrue(tile.waitForExistence(timeout: Self.wait), "no recap tile")
        XCTAssertTrue(tile.label.contains("Weekly recap"))
        tile.tap()
        for page in ["podium", "titles", "myWeek", "hottest", "meals", "bestDisclaimer"] {
            show(page, in: app)
            next(in: app)
        }
        show("ending", in: app)
        Thread.sleep(forTimeInterval: 3)
        keepScreenshot(named: "recap-12-ending-missed-en")
        XCTAssertEqual(app.buttons["recap.planNextWeek"].label, "Plan next week")
    }

    /// 动态 shows the squad's newest 战报 as its tile, clear of the tab bar, and the tile opens it.
    func testFeedTileOpensTheStory() {
        let app = launch(language: "zh-Hans", extra: ["-tab", "feed"], demo: false)
        let tile = app.buttons["recap.entry"]
        XCTAssertTrue(tile.waitForExistence(timeout: Self.wait), "动态 shows no 战报 tile")
        let bar = app.buttons["tab.feed"]
        XCTAssertTrue(bar.isSelected, "-tab feed didn't open on 动态")
        XCTAssertLessThan(tile.frame.maxY, bar.frame.minY, "the tile runs under the tab bar")
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot(named: "recap-20-feed-tile")
        tile.tap()
        show("podium", in: app)
        app.buttons["recap.close"].tap()
        XCTAssertTrue(tile.waitForExistence(timeout: Self.wait), "✕ didn't go back to 动态")
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

    /// A tap on the right of the screen, as a reader moves on.
    private func next(in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
