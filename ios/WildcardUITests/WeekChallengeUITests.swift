import XCTest

/// The challenge I accepted from 毛头 shows on the squad card's first page (Tracy, 2026-11-09):
/// what to do, who set it and 我完成了, which turns its flag into a check and 已完成. Screenshots are kept for review.
@MainActor
final class WeekChallengeUITests: XCTestCase {
    private static let wait: TimeInterval = 30

    func testIDidItMarksTodaysChallengeDone() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon",
            "-today.cardPage", "0", "-today.cardCollapsed", "0", "-uitest-challenge",
        ]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }

        let row = app.descendants(matching: .any).matching(identifier: "squadcard.challenge").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.wait), "the squad page doesn't show today's challenge")
        let title = app.descendants(matching: .any).matching(identifier: "squadcard.challenge.title").firstMatch
        XCTAssertEqual(title.label, "拉伸 5 分钟", "the challenge doesn't read 拉伸 5 分钟")
        XCTAssertTrue(app.staticTexts["毛头 · 今日挑战"].exists, "the challenge doesn't say who set it")
        let card = app.descendants(matching: .any).matching(identifier: "today.card").firstMatch
        XCTAssertTrue(card.frame.contains(row.frame), "the challenge runs off the card: \(row.frame)")
        let done = app.buttons["squadcard.challenge.complete"]
        XCTAssertTrue(done.isHittable, "我完成了 is covered")
        keepScreenshot(named: "117-week-challenge")

        done.tap()
        let marked = app.descendants(matching: .any).matching(identifier: "squadcard.challenge.done").firstMatch
        XCTAssertTrue(marked.waitForExistence(timeout: Self.wait), "我完成了 didn't mark it 已完成")
        XCTAssertFalse(done.exists, "我完成了 stayed after it was done")
        keepScreenshot(named: "118-week-challenge-done")
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
