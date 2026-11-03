import XCTest

/// The coach on the home's sideline, the way a member meets it: opening the home, 毛头 says
/// today's 战术板 line by itself, with the 教练 tag and its name; the bubble goes after its hold,
/// and tapping 毛头 says it again. The bubble stays whole on screen, clear of the card above and
/// the tab bar, and screenshots are kept for review.
@MainActor
final class CoachSidelineUITests: XCTestCase {
    /// Slow CI simulators can take many seconds to show a screen; a real failure still fails.
    private static let wait: TimeInterval = 30
    private static let line = "昨天三个人上场，我光在场边记笔记就累了。今天随缘，来了就算。"

    func testCoachSaysTodaysLine() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon",
            "-today.cardPage", "0", "-uitest-coach",
        ]
        app.launch()

        let coach = app.buttons["today.coach"]
        XCTAssertTrue(coach.waitForExistence(timeout: Self.wait), "no coach on the sideline")
        XCTAssertEqual(coach.label, "毛头")
        let bubble = app.descendants(matching: .any).matching(identifier: "today.coachLine").firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: Self.wait), "the coach didn't say today's line")
        XCTAssertTrue(bubble.label.contains("教练"), "the line has no 教练 tag: \(bubble.label)")
        XCTAssertTrue(bubble.label.contains(Self.line), "the bubble doesn't say the line: \(bubble.label)")
        expectOnScreen(bubble, in: app)
        Thread.sleep(forTimeInterval: 0.6)
        keepScreenshot(named: "61-coach-line")

        // It goes after its 6 seconds, and a tap brings it back.
        XCTAssertTrue(bubble.waitForNonExistence(timeout: Self.wait), "the coach's bubble stayed up")
        keepScreenshot(named: "62-coach-quiet")
        coach.tap()
        XCTAssertTrue(bubble.waitForExistence(timeout: Self.wait), "tapping the coach didn't say the line again")
        Thread.sleep(forTimeInterval: 0.6)
        keepScreenshot(named: "63-coach-tapped")
    }

    /// The bubble whole inside the window, under the squad card and above the tab bar.
    private func expectOnScreen(_ bubble: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        let frame = bubble.frame
        XCTAssertGreaterThanOrEqual(frame.minX, window.minX, "the bubble runs off the left: \(frame)")
        XCTAssertLessThanOrEqual(frame.maxX, window.maxX, "the bubble runs off the right: \(frame)")
        let card = app.descendants(matching: .any).matching(identifier: "today.card").firstMatch
        XCTAssertGreaterThanOrEqual(frame.minY, card.frame.maxY, "the squad card covers the bubble: \(frame)")
        let tab = app.buttons["tab.today"]
        XCTAssertTrue(tab.exists, "no tab bar under 今天")
        XCTAssertLessThanOrEqual(frame.maxY, tab.frame.minY, "the tab bar covers the bubble: \(frame)")
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
