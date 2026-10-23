import XCTest

/// 小队设置 the way a member uses it, on the in-memory squad: opened from 我, the captain's page
/// and menu, the crown winner picking the scene, and the longest names on the smallest phone.
/// Keeps screenshots for review.
@MainActor
final class SquadSettingsUITests: XCTestCase {
    func testTheCaptainsPage() {
        let app = launch()
        XCTAssertEqual(app.staticTexts["squad.name"].label, "晨跑五人组")
        XCTAssertTrue(app.staticTexts["squad.sceneLine"].label.contains("Coco"), "the line doesn't name the winner")
        XCTAssertTrue(app.buttons["squad.rename"].exists, "the captain can't rename")
        XCTAssertFalse(app.buttons["squad.changeScene"].exists, "the captain can pick though Coco won")
        XCTAssertEqual(app.buttons.matching(identifier: "squad.member.more").count, 4, "not one ··· per other member")
        assertOnScreen(app)
        settle()
        keepScreenshot(named: "60-squad-captain")

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

        app.buttons["squad.rename"].tap()
        let field = app.textFields["squad.rename.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 30), "改队名 didn't open")
        field.typeText("夜跑")
        app.buttons["squad.rename.save"].tap()
        waitFor(app.staticTexts["squad.name"], "label == '晨跑五人组夜跑'", "the new name didn't show")

        app.swipeUp()
        settle()
        keepScreenshot(named: "62-squad-bottom")
        app.buttons["squad.back"].tap()
        XCTAssertTrue(app.buttons["me.squad"].waitForExistence(timeout: 30), "返回 didn't go back to 我")
    }

    func testTheWinnerPicksTheSceneOnce() {
        let app = launch(extra: ["-squad-seat", "winner"])
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
        waitFor(app.staticTexts["squad.scene"], "label == '游泳池'", "the picked scene didn't show", timeout: 60)
        XCTAssertFalse(app.buttons["squad.changeScene"].exists, "the winner can pick twice")
        settle()
        keepScreenshot(named: "64-squad-picked")
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

    /// Opens 我, then 我的小队.
    private func launch(language: String = "zh-Hans", extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments +=
            ["-tab", "me", "-AppleLanguages", "(\(language))", "-AppleLocale", language, "-uitest-no-push"] + extra
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        let row = app.buttons["me.squad"]
        XCTAssertTrue(row.waitForExistence(timeout: 30), "我 has no squad row")
        row.tap()
        let page = app.descendants(matching: .any).matching(identifier: "squad.page").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 30), "小队设置 never showed")
        return app
    }

    /// The page's header and scene card sit inside the screen, clear of each other.
    private func assertOnScreen(_ app: XCUIApplication) {
        let screen = app.frame
        for element in [
            app.staticTexts["squad.name"], app.staticTexts["squad.scene"], app.staticTexts["squad.sceneLine"],
        ] {
            XCTAssertTrue(element.exists, "\(element.identifier) is missing")
            XCTAssertGreaterThanOrEqual(element.frame.minX, screen.minX, "\(element.identifier) starts off screen")
            XCTAssertLessThanOrEqual(element.frame.maxX, screen.maxX, "\(element.identifier) runs off screen")
        }
        XCTAssertLessThanOrEqual(
            app.staticTexts["squad.name"].frame.maxY, app.staticTexts["squad.scene"].frame.minY,
            "the name runs into the scene card")
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
