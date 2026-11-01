import XCTest

/// Hiring the squad's coach the way a captain does, on the in-memory squad: 小队设置's empty 教练
/// card, 教练市场, 毛头's 简历, 招聘, 解雇 and back; a mate reading the 简历 only; and the 简历's
/// field names on one line each, in Chinese and English. Keeps screenshots for review against
/// the approved 雇教练页面 canvas.
@MainActor
final class CoachHireUITests: XCTestCase {
    func testTheCaptainHiresAndFiresTheCoach() {
        let app = launch()
        let hire = app.buttons["squad.coach.hire"]
        XCTAssertTrue(hire.waitForExistence(timeout: 30), "the captain has no 招聘")
        settle()
        keepScreenshot(named: "82-coach-empty")

        hire.tap()
        let coach = app.buttons["coach.market.coach"].firstMatch
        XCTAssertTrue(coach.waitForExistence(timeout: 30), "教练市场 shows no coach")
        assertInside(coach, app)
        settle()
        keepScreenshot(named: "83-coach-market")

        coach.tap()
        let hireCoach = app.buttons["coach.resume.hire"]
        XCTAssertTrue(hireCoach.waitForExistence(timeout: 30), "the 简历 has no 招聘")
        assertLabelsKeepOneLine(app)
        assertClear(of: hireCoach, app)
        settle()
        keepScreenshot(named: "84-coach-resume")

        hireCoach.tap()
        let week = app.staticTexts["squad.coach.week"]
        XCTAssertTrue(week.waitForExistence(timeout: 30), "招聘 didn't end on 小队设置 with the coach")
        XCTAssertEqual(week.label, "执教第 1 周")
        XCTAssertTrue(app.buttons["squad.coach.change"].exists, "the captain can't change the coach")
        settle()
        keepScreenshot(named: "85-coach-hired")

        app.buttons["squad.coach.fire"].tap()
        let confirm = app.buttons["coach.fire.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 30), "解雇 didn't ask first")
        assertInside(confirm, app)
        settle()
        keepScreenshot(named: "86-coach-fire")

        app.buttons["coach.fire.keep"].tap()
        XCTAssertTrue(app.buttons["squad.coach.fire"].waitForExistence(timeout: 30), "先不解雇 didn't go back")
        app.buttons["squad.coach.fire"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 30), "解雇 didn't open again")
        confirm.tap()
        XCTAssertTrue(hire.waitForExistence(timeout: 30), "确认解雇 didn't leave the squad without a coach")
    }

    func testAMateReadsTheResumeOnly() {
        let app = launch(extra: ["-squad-seat", "coachedMember"])
        let open = app.buttons["squad.coach.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 30), "the mate doesn't see the squad's coach")
        XCTAssertFalse(app.buttons["squad.coach.change"].exists, "a mate can change the coach")
        XCTAssertFalse(app.buttons["squad.coach.fire"].exists, "a mate can fire the coach")
        open.tap()
        let captainOnly = app.staticTexts["coach.resume.captainOnly"]
        XCTAssertTrue(captainOnly.waitForExistence(timeout: 30), "the 简历 doesn't say only the captain hires")
        XCTAssertFalse(app.buttons["coach.resume.hire"].exists, "a mate can hire")
        assertLabelsKeepOneLine(app)
        settle()
        keepScreenshot(named: "87-coach-resume-mate")
    }

    /// English names are the longest; they still keep one line each.
    func testTheResumeInEnglish() {
        let app = launch(language: "en", extra: ["-squad-seat", "coached"])
        let open = app.buttons["squad.coach.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 30), "the captain doesn't see the squad's coach")
        open.tap()
        XCTAssertTrue(app.staticTexts["Expected pay"].waitForExistence(timeout: 30), "the 简历 isn't in English")
        assertLabelsKeepOneLine(app)
        settle()
        keepScreenshot(named: "88-coach-resume-en")
    }

    /// Opens 我, then 设置, then 我的小队.
    private func launch(language: String = "zh-Hans", extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments +=
            ["-tab", "me", "-AppleLanguages", "(\(language))", "-AppleLocale", language, "-uitest-no-push"] + extra
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        let settings = app.buttons["me.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 30), "我 never showed")
        settings.tap()
        let row = app.buttons["me.squad"]
        XCTAssertTrue(row.waitForExistence(timeout: 30), "设置 has no squad row")
        row.tap()
        let page = app.descendants(matching: .any).matching(identifier: "squad.page").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 30), "小队设置 never showed")
        return app
    }

    /// Each of the 简历's field names (履历, 执教, 风格, 期望待遇) is one line: as tall as the
    /// shortest, and inside the screen.
    private func assertLabelsKeepOneLine(_ app: XCUIApplication) {
        let labels = app.staticTexts.matching(identifier: "coach.resume.label").allElementsBoundByIndex
        XCTAssertEqual(labels.count, 4, "the 简历 doesn't show its four fields")
        let heights = labels.map(\.frame.height)
        guard let shortest = heights.min() else { return }
        for label in labels {
            XCTAssertLessThan(label.frame.height, shortest * 1.5, "「\(label.label)」 wraps onto a second line")
            assertInside(label, app)
        }
    }

    private func assertInside(_ element: XCUIElement, _ app: XCUIApplication) {
        XCTAssertGreaterThanOrEqual(element.frame.minX, app.frame.minX, "\(element.label) starts off screen")
        XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX, "\(element.label) runs off screen")
        XCTAssertLessThanOrEqual(element.frame.maxY, app.frame.maxY, "\(element.label) runs off the bottom")
    }

    /// The 简历's fields end above 招聘, which stays on screen.
    private func assertClear(of button: XCUIElement, _ app: XCUIApplication) {
        assertInside(button, app)
        for label in app.staticTexts.matching(identifier: "coach.resume.label").allElementsBoundByIndex
        where label.isHittable {
            XCTAssertLessThanOrEqual(label.frame.maxY, button.frame.minY, "「\(label.label)」 sits under 招聘")
        }
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
