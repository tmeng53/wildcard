import XCTest

/// The coach on the home's sideline, the way a member meets it: 毛头 stands there saying nothing
/// by itself, and a tap pops up its card (Tracy, 2026-11-05) with today's 战术板 over it; a tap
/// off the card closes it, and a tap on the 战术板 opens 动态. Screenshots are kept for review.
@MainActor
final class CoachSidelineUITests: XCTestCase {
    /// Slow CI simulators can take many seconds to show a screen; a real failure still fails.
    private static let wait: TimeInterval = 30
    private static let line = "昨天三个人上场，我光在场边记笔记就累了。今天随缘，来了就算。"

    func testTappingTheCoachOpensItsCard() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon",
            "-today.cardPage", "0", "-uitest-coach",
        ]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }

        let coach = app.buttons["today.coach"]
        XCTAssertTrue(coach.waitForExistence(timeout: Self.wait), "no coach on the sideline")
        XCTAssertEqual(coach.label, "毛头")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertFalse(labeled(Self.line, in: app).exists, "the coach still says its line on the home")
        keepScreenshot(named: "61-coach-sideline")

        coach.tap()
        let card = element("coachCard", in: app)
        XCTAssertTrue(card.waitForExistence(timeout: Self.wait), "tapping the coach didn't open its card")
        XCTAssertFalse(element("coach.resume", in: app).exists, "the home opened the 简历 instead of the card")
        XCTAssertTrue(card.label.contains("混混教练"), "the card doesn't wear the coach's title: \(card.label)")
        XCTAssertTrue(card.label.contains("带队 1 天"), "the card doesn't count its days: \(card.label)")
        XCTAssertFalse(labeled("轻点翻面", in: app).exists, "the coach's card says it turns over")
        let board = app.buttons["coachCard.board"]
        XCTAssertTrue(board.waitForExistence(timeout: Self.wait), "no 战术板 over the card")
        XCTAssertTrue(board.label.contains(Self.line), "the board doesn't show today's line: \(board.label)")
        let screen = app.windows.firstMatch.frame
        XCTAssertTrue(screen.contains(board.frame), "the board runs off the screen: \(board.frame)")
        XCTAssertTrue(screen.contains(card.frame), "the card runs off the screen: \(card.frame)")
        XCTAssertLessThanOrEqual(board.frame.maxY, card.frame.minY, "the board covers the card")
        Thread.sleep(forTimeInterval: 0.6)
        keepScreenshot(named: "62-coach-card")

        // A tap off the card closes it, back on the home.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)).tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: Self.wait), "a tap off the card didn't close it")
        XCTAssertTrue(app.buttons["today.checkin"].waitForExistence(timeout: Self.wait), "the home is gone")

        // The 战术板 opens 动态, where it tops today.
        coach.tap()
        XCTAssertTrue(board.waitForExistence(timeout: Self.wait), "the card didn't open again")
        board.tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: Self.wait), "the card stayed over 动态")
        XCTAssertTrue(
            element("feed.coachBoard", in: app).waitForExistence(timeout: Self.wait), "the 战术板 didn't open 动态")
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
