import XCTest

/// Hiring the squad's coach the way a captain does, on the in-memory squad: 小队设置's empty 教练
/// card, 教练招聘会, 毛头's 简历, 招聘, then 解雇 from the 简历 and back; a mate reading the 简历 only; and the 简历's
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
        XCTAssertTrue(coach.waitForExistence(timeout: 30), "教练招聘会 shows no coach")
        assertInside(coach, app)
        settle()
        keepScreenshot(named: "83-coach-market")

        let hireCoach = app.buttons["coach.resume.hire"]
        tap(coach, until: hireCoach, "exists == true", "the 简历 has no 招聘")
        assertLabelsKeepOneLine(app)
        assertClear(of: hireCoach, app)
        settle()
        keepScreenshot(named: "84-coach-resume")

        hireCoach.tap()
        let tenure = app.staticTexts["squad.coach.tenure"]
        XCTAssertTrue(tenure.waitForExistence(timeout: 30), "招聘 didn't end on 小队设置 with the coach")
        XCTAssertEqual(tenure.label, "执教 1 天")
        XCTAssertFalse(app.buttons["squad.coach.change"].exists, "换教练 is still on the card")
        XCTAssertFalse(app.buttons["squad.coach.fire"].exists, "解雇 is still on the card")
        settle()
        keepScreenshot(named: "85-coach-hired")

        // 换教练 and 解雇 wait on the coach's 简历, small.
        app.buttons["squad.coach.open"].tap()
        let fire = app.buttons["coach.resume.fire"]
        XCTAssertTrue(fire.waitForExistence(timeout: 30), "the 简历 has no 解雇 for the captain")
        XCTAssertTrue(app.buttons["coach.resume.change"].exists, "the 简历 has no 换教练 for the captain")
        XCTAssertFalse(app.buttons["coach.resume.hire"].exists, "the squad's own coach offers 招聘")
        assertClear(of: fire, app)
        settle()
        keepScreenshot(named: "85-coach-resume-manage")

        fire.tap()
        let confirm = app.buttons["coach.fire.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 30), "解雇 didn't ask first")
        assertInside(confirm, app)
        settle()
        keepScreenshot(named: "86-coach-fire")

        app.buttons["coach.fire.keep"].tap()
        XCTAssertTrue(fire.waitForExistence(timeout: 30), "先不解雇 didn't go back to the 简历")
        fire.tap()
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
        XCTAssertFalse(app.buttons["coach.resume.fire"].exists, "a mate can fire the coach from the 简历")
        let captainOnly = app.staticTexts["coach.resume.captainOnly"]
        XCTAssertTrue(captainOnly.waitForExistence(timeout: 30), "the 简历 doesn't say only the captain hires")
        XCTAssertFalse(app.buttons["coach.resume.hire"].exists, "a mate can hire")
        assertLabelsKeepOneLine(app)
        settle()
        keepScreenshot(named: "87-coach-resume-mate")
    }

    /// A mate browses 教练招聘会 and reads each 简历, but can't hire from it (Tracy, 2026-11-03).
    func testAMateBrowsesTheMarketOnly() {
        let app = launch(extra: ["-squad-seat", "member"])
        let browse = app.buttons["squad.coach.browse"]
        XCTAssertTrue(browse.waitForExistence(timeout: 30), "a mate can't browse 教练招聘会")
        XCTAssertFalse(app.buttons["squad.coach.hire"].exists, "a mate can hire")
        browse.tap()
        let coach = app.buttons["coach.market.coach"].firstMatch
        XCTAssertTrue(coach.waitForExistence(timeout: 30), "逛逛招聘会 doesn't list the coaches")
        settle()
        keepScreenshot(named: "89-coach-market-mate")
        coach.tap()
        let captainOnly = app.staticTexts["coach.resume.captainOnly"]
        XCTAssertTrue(captainOnly.waitForExistence(timeout: 30), "the 简历 doesn't say only the captain hires")
        XCTAssertFalse(app.buttons["coach.resume.hire"].exists, "a mate can hire from 教练招聘会")
    }

    /// English names are the longest; they still keep one line each. 教练招聘会 counts its
    /// coaches.
    func testTheResumeInEnglish() {
        let app = launch(language: "en", extra: ["-squad-seat", "coached"])
        let open = app.buttons["squad.coach.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 30), "the captain doesn't see the squad's coach")
        open.tap()
        XCTAssertTrue(app.staticTexts["Expected pay"].waitForExistence(timeout: 30), "the 简历 isn't in English")
        assertLabelsKeepOneLine(app)
        settle()
        keepScreenshot(named: "88-coach-resume-en")
        // 换教练 waits on the coach's 简历 and opens 教练招聘会.
        app.buttons["coach.resume.change"].tap()
        XCTAssertTrue(
            app.staticTexts["2 coaches looking for a squad"].waitForExistence(timeout: 30),
            "教练招聘会 doesn't count its coaches")
    }

    /// 换教练 asks first, since the coach the squad has leaves: 毛头 crying, that he leaves and
    /// 帕帕 comes; 先不换 goes back, 确认换教练 goes back to 今天.
    func testTheCaptainConfirmsChangingTheCoach() {
        let app = launch(extra: ["-squad-seat", "coached"])
        let open = app.buttons["squad.coach.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 30), "the captain doesn't see the squad's coach")
        open.tap()
        let change = app.buttons["coach.resume.change"]
        XCTAssertTrue(change.waitForExistence(timeout: 30), "the 简历 has no 换教练 for the captain")
        change.tap()
        let coaches = app.buttons.matching(identifier: "coach.market.coach")
        XCTAssertTrue(coaches.element(boundBy: 1).waitForExistence(timeout: 30), "教练招聘会 shows no other coach")
        let hireCoach = app.buttons["coach.resume.hire"]
        tap(coaches.element(boundBy: 1), until: hireCoach, "exists == true", "帕帕's 简历 has no 招聘")
        hireCoach.tap()

        let confirm = app.buttons["coach.swap.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 30), "换教练 didn't ask first")
        XCTAssertTrue(app.staticTexts["毛头会离开，帕帕会来"].exists, "换教练 doesn't say who leaves and who comes")
        assertInside(confirm, app)
        settle()
        keepScreenshot(named: "90-coach-swap")

        app.buttons["coach.swap.keep"].tap()
        XCTAssertTrue(hireCoach.waitForExistence(timeout: 30), "先不换 didn't go back to the 简历")
        hireCoach.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 30), "换教练 didn't ask again")
        confirm.tap()
        // The coaches change places on 今天 (CoachLetterUITests follows the letter).
        XCTAssertTrue(
            app.descendants(matching: .any)["today.handover"].waitForExistence(timeout: 30),
            "确认换教练 didn't go back to 今天 for the handover")
    }

    /// A squad without a coach has its empty spot on the home's sideline, 「招聘教练」, which opens
    /// 教练招聘会 straight from 今天 (approved 2026-11-08).
    func testTheHomesEmptySidelineOpensTheMarket() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push"]
        // Home opens on the folded capsule, as these tests were written for.
        app.launchArguments.append("-uitest-card-folded")
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        let vacancy = app.buttons["today.coachVacancy"]
        XCTAssertTrue(vacancy.waitForExistence(timeout: 30), "今天 has no empty spot for a coach")
        assertInside(vacancy, app)
        XCTAssertFalse(app.buttons["today.coach"].exists, "a coach stands on a squad that has none")
        settle()
        keepScreenshot(named: "81-coach-vacancy")

        vacancy.tap()
        let coach = app.buttons["coach.market.coach"].firstMatch
        XCTAssertTrue(coach.waitForExistence(timeout: 30), "the empty spot didn't open 教练招聘会")
    }

    /// Opens 我, then 设置, then 我的小队.
    private func launch(language: String = "zh-Hans", extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments +=
            ["-tab", "squad", "-AppleLanguages", "(\(language))", "-AppleLocale", language, "-uitest-no-push"] + extra
        // Home opens on the folded capsule, as these tests were written for.
        app.launchArguments.append("-uitest-card-folded")
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        let page = app.descendants(matching: .any).matching(identifier: "squad.page").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 30), "小队 never showed")
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
