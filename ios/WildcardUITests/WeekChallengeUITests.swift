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

    /// A tap on the coach's head on the challenge row opens that challenge's card on the coach's
    /// page, and 返回 lands on the coach's page (Tracy, 2026-11-10).
    func testTheCoachsHeadOpensTheChallengesCard() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon",
            "-today.cardPage", "0", "-today.cardCollapsed", "0", "-uitest-challenge", "-uitest-coach",
            "-uitest-coach-seen",
        ]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }

        let head = app.buttons["squadcard.challenge.coach"]
        XCTAssertTrue(head.waitForExistence(timeout: Self.wait), "the challenge's coach isn't a button")
        XCTAssertTrue(head.isHittable, "the challenge's coach is covered")
        head.tap()
        let challenge = app.descendants(matching: .any).matching(identifier: "coachDeck.challenge").firstMatch
        XCTAssertTrue(challenge.waitForExistence(timeout: Self.wait), "the challenge's card didn't open")
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot(named: "119-week-challenge-card")
        XCTAssertTrue(challenge.label.contains("拉伸"), "the card opened isn't today's challenge: \(challenge.label)")
        XCTAssertTrue(
            app.windows.firstMatch.frame.contains(challenge.frame), "the card runs off the screen: \(challenge.frame)")
        app.navigationBars.buttons.firstMatch.tap()
        let history = app.buttons["coachDeck.history"]
        XCTAssertTrue(history.waitForExistence(timeout: Self.wait), "返回 didn't land on the coach's page")
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
