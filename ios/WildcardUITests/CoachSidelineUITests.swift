import XCTest

/// The coach on the home's sideline, the way a member meets it: 毛头 stands there saying nothing
/// by itself, and a tap opens its page (Tracy, 2026-11-08), whose top right opens 教练招聘会 and
/// its 简历. Screenshots are kept for review.
@MainActor
final class CoachSidelineUITests: XCTestCase {
    /// Slow CI simulators can take many seconds to show a screen; a real failure still fails.
    private static let wait: TimeInterval = 30
    private static let line = "昨天三个人上场，我光在场边记笔记就累了。今天随缘，来了就算。"

    func testTappingTheCoachOpensItsPage() {
        continueAfterFailure = false
        let app = launch()
        let coach = app.buttons["today.coach"]
        XCTAssertTrue(coach.waitForExistence(timeout: Self.wait), "no coach on the sideline")
        XCTAssertEqual(coach.label, "毛头")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertFalse(labeled(Self.line, in: app).exists, "the coach still says its line on the home")
        keepScreenshot(named: "61-coach-sideline")

        coach.tap()
        let top = element("coachDeck.card.board", in: app)
        XCTAssertTrue(top.waitForExistence(timeout: Self.wait), "tapping the coach didn't open its page")
        XCTAssertTrue(app.navigationBars["毛头"].exists, "the page isn't 毛头's")
        // Back goes home.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["today.checkin"].waitForExistence(timeout: Self.wait), "back didn't go home")
    }

    /// 招聘会 and 简历, top right on the coach's page.
    func testTheCoachsPageOpensTheMarketAndItsResume() {
        continueAfterFailure = false
        let app = launch()
        let coach = app.buttons["today.coach"]
        XCTAssertTrue(coach.waitForExistence(timeout: Self.wait), "no coach on the sideline")
        coach.tap()
        let resume = app.buttons["coachDeck.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: Self.wait), "the page has no 简历")
        resume.tap()
        XCTAssertTrue(element("coach.resume", in: app).waitForExistence(timeout: Self.wait), "简历 didn't open")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let market = app.buttons["coachDeck.market"]
        XCTAssertTrue(market.waitForExistence(timeout: Self.wait), "back didn't return to the coach's page")
        market.tap()
        XCTAssertTrue(
            app.buttons["coach.market.coach"].firstMatch.waitForExistence(timeout: Self.wait),
            "招聘会 didn't open 教练招聘会")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon",
            "-today.cardPage", "0", "-uitest-coach",
        ]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Any element showing exactly `label`.
    private func labeled(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
