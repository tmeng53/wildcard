import XCTest

/// 小队 the way a member uses it, on the in-memory squad: its page from home, the row of heads, the
/// captain's page and menu, the crown winner picking the scene, and the longest names on the smallest phone.
/// Keeps screenshots for review.
@MainActor
final class SquadSettingsUITests: XCTestCase {
    func testTheCaptainsPage() {
        let app = launch()
        XCTAssertEqual(app.staticTexts["squad.name"].label, "晨跑五人组")
        XCTAssertTrue(app.buttons["squad.goal.pick.3"].isSelected, "the goal's pill isn't on 3")
        XCTAssertEqual(app.staticTexts["squad.goal.note"].label, "改动下周生效")
        XCTAssertTrue(
            app.descendants(matching: .any)["squad.member.captain"].exists, "the captain's row has no 队长 tag")
        XCTAssertTrue(app.buttons["squad.rename"].exists, "the captain can't rename")
        XCTAssertFalse(app.buttons["squad.changeScene"].exists, "the captain can pick though Coco won")
        XCTAssertEqual(app.buttons.matching(identifier: "squad.member.more").count, 4, "not one ··· per other member")
        XCTAssertTrue(backButton(in: app).exists, "the page has no way back")
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "squad.head").count, 5, "not one head per member")
        XCTAssertTrue(app.descendants(matching: .any)["squad.head.coach"].exists, "no coach in the row of heads")
        XCTAssertTrue(app.buttons["squad.head.invite"].exists, "no 邀请 in the row of heads")
        assertOnScreen(app)
        settle()
        keepScreenshot(named: "60-squad-captain")

        // The captain's change counts from next week: this week's number stays, the line says so.
        app.buttons["squad.goal.pick.5"].tap()
        waitFor(app.staticTexts["squad.goal.note"], "label == '下周起人均 5 天'", "the change didn't wait for next week")
        XCTAssertTrue(app.buttons["squad.goal.pick.5"].isSelected, "the pill didn't move to 5")

        app.buttons.matching(identifier: "squad.member.more").element(boundBy: 3).tap()
        let remove = app.buttons["squad.member.remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 30), "the ··· menu didn't open")
        settle()
        keepScreenshot(named: "61-squad-member-menu")
        remove.tap()
        let confirm = app.buttons.matching(identifier: "squad.remove.confirm").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 30), "removing didn't ask first")
        confirm.tap()
        waitFor(
            app.buttons.matching(identifier: "squad.member.more").element(boundBy: 3), "exists == false",
            "大卫 is still in the squad")
        // SwiftUI drops an alert asked for while the glass menu is still going away.
        waitFor(confirm, "exists == false", "the glass menu didn't close")
        settle()

        // The page stays disabled while the removal saves, and a tap then does nothing.
        let rename = app.buttons["squad.rename"]
        waitFor(rename, "isEnabled == true", "the page stayed disabled after removing")
        rename.tap()
        // The system alert may not carry the field's and button's identifiers, so find them in it.
        let alert = app.alerts.firstMatch
        let field = alert.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 30), "改队名 didn't open")
        field.typeText("夜跑")
        // More than one element in the alert can match 保存, so take the first.
        alert.buttons.matching(NSPredicate(format: "label == '保存'")).firstMatch.tap()
        waitFor(app.staticTexts["squad.name"], "label == '晨跑五人组夜跑'", "the new name didn't show")

        app.swipeUp()
        settle()
        keepScreenshot(named: "62-squad-bottom")
        XCTAssertFalse(app.buttons["squad.pastRecaps"].exists, "往期战报 is back on 小队; the 战报 live in 动态")
    }

    func testTheWinnerPicksTheSceneOnce() {
        // Home's card opens unfolded, for the squad's name at the end.
        let app = launch(extra: ["-squad-seat", "winner", "-today.cardCollapsed", "0"])
        XCTAssertFalse(app.buttons["squad.rename"].exists, "a member can rename")
        XCTAssertEqual(app.buttons.matching(identifier: "squad.member.more").count, 0, "a member manages others")
        app.buttons["squad.changeScene"].tap()
        let pool = app.buttons["squad.scene.pool"]
        XCTAssertTrue(pool.waitForExistence(timeout: 30), "the tiles didn't open")
        pool.tap()
        assertOnScreen(app)
        settle()
        keepScreenshot(named: "63-squad-picker")
        app.buttons["squad.scene.confirm"].tap()
        // Every pick ends on home: the reveal fills the screen with the pool, the page goes, and
        // the squad drops onto the scene one after another, me last.
        let page = app.descendants(matching: .any).matching(identifier: "squad.page").firstMatch
        waitFor(page, "exists == false", "the page didn't go after the reveal", timeout: 60)
        // Frames a few times a second, to review the drop against the prototype.
        let start = Date()
        for frame in 0..<12 {
            keepScreenshot(
                named: String(
                    format: "64-squad-picked-dropping-%02d-%04dms", frame, Int(Date().timeIntervalSince(start) * 1000)))
        }
        let card = app.descendants(matching: .any)["today.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 30), "home didn't take over")
        Thread.sleep(forTimeInterval: 2.5)
        keepScreenshot(named: "64-squad-picked-home")
        // Back on 小队 through home's card (the tab bar steps aside for the drop, and the
        // system's bar comes back without its items' identifiers), the pick is locked for the week.
        app.descendants(matching: .any)["squadcard.squad"].tap()
        waitFor(app.staticTexts["squad.scene"], "label == '游泳池'", "the picked scene didn't show", timeout: 60)
        XCTAssertFalse(app.buttons["squad.changeScene"].exists, "the winner can pick twice")
    }

    /// 比赛时区, on 小队设置 from the header's gear: the captain picks a zone from the system's
    /// list, which counts at once; a member reads the row and can't open it.
    func testTheCaptainChangesTheMatchTimeZone() {
        let app = launch()
        XCTAssertFalse(app.descendants(matching: .any)["squad.timeZone"].exists, "比赛时区 is still on 小队")
        let gear = app.buttons["squad.preferences.open"]
        XCTAssertTrue(gear.waitForExistence(timeout: 30), "no 小队设置 on 小队's header")
        gear.tap()
        let row = app.buttons["squad.timeZone"]
        XCTAssertTrue(row.waitForExistence(timeout: 30), "no 比赛时区 on the captain's 小队设置")
        XCTAssertTrue(app.buttons["squad.leave"].exists, "no 退出小队 on 小队设置")
        XCTAssertTrue(row.label.contains(region("Asia/Taipei")), "the row doesn't show the squad's zone: \(row.label)")
        XCTAssertLessThanOrEqual(row.frame.maxX, app.frame.maxX, "the 比赛时区 row runs off the screen")
        settle()
        keepScreenshot(named: "67-squad-time-zone")
        row.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 30), "the zone list didn't open")
        search.tap()
        search.typeText("New York")
        let newYork = app.buttons["squad.timeZone.America/New_York"]
        XCTAssertTrue(newYork.waitForExistence(timeout: 30), "searching New York finds no zone")
        newYork.tap()
        waitFor(row, "label CONTAINS '\(region("America/New_York"))'", "the change didn't count at once", timeout: 30)
        XCTAssertFalse(app.staticTexts["squad.timeZone.next"].exists, "the change waits for next week")
        settle()
        keepScreenshot(named: "68-squad-time-zone-changed")

        app.terminate()
        let member = launch(extra: ["-squad-seat", "member"])
        let memberGear = member.buttons["squad.preferences.open"]
        XCTAssertTrue(memberGear.waitForExistence(timeout: 30), "a member has no 小队设置")
        memberGear.tap()
        let read = member.descendants(matching: .any)["squad.timeZone"]
        XCTAssertTrue(read.waitForExistence(timeout: 30), "a member doesn't see 比赛时区")
        XCTAssertFalse(member.buttons["squad.timeZone"].exists, "a member can open the zone list")
        settle()
        keepScreenshot(named: "69-squad-time-zone-member")
    }

    /// A zone's name as 小队设置 shows it in Simplified Chinese (北美东部时间).
    private func region(_ identifier: String) -> String {
        TimeZone(identifier: identifier)?.localizedName(for: .generic, locale: Locale(identifier: "zh-Hans"))
            ?? identifier
    }

    /// The longest names the rules allow stay inside the screen on the smallest phone.
    func testLongNamesFit() {
        let app = launch(extra: ["-uitest-long-names", "-squad-seat", "noWinner"])
        assertOnScreen(app)
        for row in app.descendants(matching: .any).matching(identifier: "squad.member").allElementsBoundByIndex
        where row.isHittable {
            XCTAssertLessThanOrEqual(row.frame.maxX, app.frame.maxX, "a member row runs off the screen")
        }
        settle()
        keepScreenshot(named: "65-squad-long-names")
    }

    func testInEnglish() {
        let app = launch(language: "en")
        XCTAssertTrue(app.staticTexts["This week's spot"].exists, "小队设置 isn't in English")
        settle()
        keepScreenshot(named: "66-squad-en")
    }

    /// Opens on 小队.
    private func launch(language: String = "zh-Hans", extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments +=
            ["-tab", "squad", "-AppleLanguages", "(\(language))", "-AppleLocale", language, "-uitest-no-push"] + extra
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        let page = app.descendants(matching: .any).matching(identifier: "squad.page").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 30), "小队 never showed")
        return app
    }

    /// The page's header and scene card sit inside the screen, clear of each other.
    private func assertOnScreen(_ app: XCUIApplication) {
        let screen = app.frame
        for element in [
            app.staticTexts["squad.name"], app.staticTexts["squad.scene"],
            app.descendants(matching: .any)["squad.goal.now"],
        ] {
            XCTAssertTrue(element.exists, "\(element.identifier) is missing")
            XCTAssertGreaterThanOrEqual(element.frame.minX, screen.minX, "\(element.identifier) starts off screen")
            XCTAssertLessThanOrEqual(element.frame.maxX, screen.maxX, "\(element.identifier) runs off screen")
        }
        XCTAssertLessThanOrEqual(
            app.staticTexts["squad.name"].frame.maxY, app.descendants(matching: .any)["squad.goal.now"].frame.minY,
            "the name runs into the goal card")
        if app.buttons["squad.rename"].exists {
            XCTAssertLessThanOrEqual(
                app.staticTexts["squad.name"].frame.maxX, app.buttons["squad.rename"].frame.minX,
                "the name runs under the rename button")
        }
    }

    /// The characters and springs settle before a screenshot.
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
