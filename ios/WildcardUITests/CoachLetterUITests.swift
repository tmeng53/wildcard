import XCTest

/// The coach's handover letter (交接信), on the in-memory squad: after 确认换教练 the old coach writes
/// on 今天's sideline under 「交接中」 while the new one waits beside it, throws the envelope once the
/// letter is written and walks off; the seal opens it, 收下 puts it away, and the new coach's 简历
/// keeps it to read again. A mate sees the envelope on their next 今天. Keeps screenshots for review
/// against the approved 交接信 prototype.
@MainActor
final class CoachLetterUITests: XCTestCase {
    func testTheCaptainChangesTheCoachAndReadsTheLetter() {
        let app = launch(["-tab", "squad", "-squad-seat", "coached"])
        let page = app.descendants(matching: .any).matching(identifier: "squad.page").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 30), "小队 never showed")
        app.buttons["squad.coach.open"].tap()
        let change = app.buttons["coach.resume.change"]
        XCTAssertTrue(change.waitForExistence(timeout: 30), "the 简历 has no 换教练 for the captain")
        change.tap()
        let coaches = app.buttons.matching(identifier: "coach.market.coach")
        XCTAssertTrue(coaches.element(boundBy: 1).waitForExistence(timeout: 30), "教练招聘会 shows no other coach")
        let hire = app.buttons["coach.resume.hire"]
        tap(coaches.element(boundBy: 1), until: hire, "exists == true", "帕帕's 简历 has no 招聘")
        hire.tap()
        let confirm = app.buttons["coach.swap.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 30), "换教练 didn't ask first")
        confirm.tap()

        let handover = app.descendants(matching: .any)["today.handover"]
        XCTAssertTrue(handover.waitForExistence(timeout: 30), "今天 shows no 交接中 while the letter is written")
        assertInside(handover, app)
        keepScreenshot(named: "91a-coach-handover")

        let seal = app.buttons["today.letter.seal"]
        XCTAssertTrue(seal.waitForExistence(timeout: 30), "the written letter never came as an envelope")
        XCTAssertFalse(handover.exists, "「交接中」 stays after the letter came")
        settle()
        assertInside(seal, app)
        keepScreenshot(named: "91b-coach-letter-sealed")

        seal.tap()
        let putAway = app.buttons["today.letter.putAway"]
        waitForHittable(putAway, "the opened letter has no 收下")
        settle()
        assertInside(putAway, app)
        assertInside(app.descendants(matching: .any)["today.letter"], app)
        keepScreenshot(named: "91c-coach-letter")

        putAway.tap()
        let coach = app.descendants(matching: .any)["today.coach"]
        waitFor(coach, "label == '帕帕'", "帕帕 doesn't stand on the sideline after 收下")
        XCTAssertFalse(seal.exists, "the letter shows again after 收下")
        settle()
        keepScreenshot(named: "91d-coach-after-letter")

        readTheLetterAgain(in: app)
    }

    /// The new coach's 简历 keeps the letter to read again. The squad card starts folded into its
    /// capsule, which opens it first.
    private func readTheLetterAgain(in app: XCUIApplication) {
        let squadName = app.descendants(matching: .any)["squadcard.squad"]
        if !squadName.exists { app.buttons["squadcard.capsule"].tap() }
        XCTAssertTrue(squadName.waitForExistence(timeout: 30), "the squad card didn't open")
        squadName.tap()
        let open = app.buttons["squad.coach.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 30), "小队 didn't open from 今天")
        open.tap()
        let again = app.buttons["coach.resume.letter"]
        XCTAssertTrue(again.waitForExistence(timeout: 30), "帕帕's 简历 has no 毛头的交接信")
        again.tap()
        let sheet = app.buttons["today.letter.putAway"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 30), "毛头的交接信 doesn't open the letter")
        settle()
        assertInside(sheet, app)
        keepScreenshot(named: "91e-coach-letter-again")
    }

    /// A mate whose squad changed coach finds the envelope on 今天, once.
    func testAMateFindsTheEnvelopeOnToday() {
        let app = launch(["-uitest-coach-letter"])
        let seal = app.buttons["today.letter.seal"]
        XCTAssertTrue(seal.waitForExistence(timeout: 30), "the mate's 今天 shows no envelope")
        settle()
        assertInside(seal, app)
        keepScreenshot(named: "91f-coach-letter-mate")
        seal.tap()
        let putAway = app.buttons["today.letter.putAway"]
        waitForHittable(putAway, "the opened letter has no 收下")
        putAway.tap()
        let coach = app.descendants(matching: .any)["today.coach"]
        waitFor(coach, "label == '帕帕'", "帕帕 isn't on the sideline")
        XCTAssertFalse(seal.exists, "the letter shows again after 收下")
    }

    /// A long letter at the largest type scrolls inside the sheet, and 收下 stays on screen.
    func testALongLetterAtTheLargestTypeScrollsAndKeepsItsButton() {
        let app = launch([
            "-uitest-coach-letter", "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        let seal = app.buttons["today.letter.seal"]
        XCTAssertTrue(seal.waitForExistence(timeout: 30), "the mate's 今天 shows no envelope")
        seal.tap()
        let putAway = app.buttons["today.letter.putAway"]
        waitForHittable(putAway, "收下 is out of reach at the largest type")
        settle()
        assertInside(putAway, app)
        let text = app.descendants(matching: .any)["today.letter.text"]
        XCTAssertTrue(text.exists, "the letter's lines are gone")
        app.scrollViews.containing(.any, identifier: "today.letter.text").firstMatch.swipeUp()
        XCTAssertTrue(putAway.isHittable, "收下 went away when the letter scrolled")
        keepScreenshot(named: "91g-coach-letter-largest-type")
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments +=
            ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon"] + extra
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        return app
    }

    private func assertInside(_ element: XCUIElement, _ app: XCUIApplication) {
        XCTAssertGreaterThanOrEqual(element.frame.minX, app.frame.minX, "\(element.label) starts off screen")
        XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX, "\(element.label) runs off screen")
        XCTAssertLessThanOrEqual(element.frame.maxY, app.frame.maxY, "\(element.label) runs off the bottom")
    }

    /// The springs settle before a screenshot.
    private func settle() {
        Thread.sleep(forTimeInterval: 1)
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
