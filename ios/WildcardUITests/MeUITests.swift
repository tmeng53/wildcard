import XCTest

/// 我 the way a member uses it, on the in-memory member: the player card and its back, 设置 with
/// the notification switch, and the 注销账号 page. Keeps screenshots for review.
@MainActor
final class MeUITests: XCTestCase {
    func testPlayerCard() {
        let app = launch(language: "zh-Hans")
        let page = app.descendants(matching: .any).matching(identifier: "me.page").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 30), "我 never showed")
        let card = app.buttons["me.card"]
        XCTAssertTrue(card.label.contains("小林"), "the card has no nickname: \(card.label)")
        XCTAssertTrue(card.label.contains("周三不练腿俱乐部"), "the card has no squad: \(card.label)")
        XCTAssertTrue(card.label.contains("128"), "the card has no lifetime count: \(card.label)")
        XCTAssertTrue(card.label.contains("3/5"), "the card has no 本周: \(card.label)")
        XCTAssertTrue(card.label.contains("22号"), "the card has no number: \(card.label)")
        XCTAssertTrue(card.label.contains("SINCE 2026"), "the card has no join year: \(card.label)")
        XCTAssertTrue(card.label.contains("早八战神"), "the card has no latest title: \(card.label)")
        XCTAssertTrue(app.buttons["tab.me"].isSelected, "the 我 tab isn't the selected one")
        assertClearOfTabBar(app.buttons["me.editCharacter"], in: app)
        settle()
        keepScreenshot(named: "40-me")

        // A tap turns the card over to the career numbers, and another turns it back.
        card.tap()
        waitFor(card, "label CONTAINS '放纵餐'", "the card didn't turn over to the other kinds")
        XCTAssertTrue(card.label.contains("46"), "the back has no 健康餐 count: \(card.label)")
        XCTAssertTrue(card.label.contains("最常练"), "the back has no 最常练: \(card.label)")
        XCTAssertTrue(card.label.contains("跑步"), "the back has no top sport: \(card.label)")
        XCTAssertTrue(card.label.contains("×2"), "the back has no title count: \(card.label)")
        settle()
        keepScreenshot(named: "41-me-card-back")
        card.tap()
        waitFor(card, "NOT (label CONTAINS '放纵餐')", "the card didn't turn back")
    }

    /// 我的动态 from 我: the member's own posts as a wall under its month, the header's counts, a
    /// kind with nothing in it, and back to 我.
    func testMyPostsWall() {
        let app = launch(language: "zh-Hans")
        let entry = app.buttons["me.myPosts"]
        XCTAssertTrue(entry.waitForExistence(timeout: 30), "我 has no 我的动态 button")
        entry.tap()
        let wall = app.descendants(matching: .any).matching(identifier: "wall.page").firstMatch
        XCTAssertTrue(wall.waitForExistence(timeout: 30), "我的动态 never opened")
        let tile = app.descendants(matching: .any).matching(identifier: "wall.tile").firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 30), "the wall has no tiles")
        XCTAssertTrue(
            app.staticTexts["wall.counts"].label.contains("发过 1 条"),
            "the header has no counts: \(app.staticTexts["wall.counts"].label)")
        XCTAssertTrue(tile.frame.maxX <= app.frame.maxX && tile.frame.minX >= 0, "a tile runs off the screen")
        settle()
        keepScreenshot(named: "92-my-posts")

        // A tile opens 动态's own post page, without the tab bar, and 返回 comes back to the wall.
        tile.tap()
        let back = app.buttons["post.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 30), "a tile didn't open the post's page")
        XCTAssertFalse(app.buttons["tab.feed"].exists, "the tab bar stayed over the post's page")
        settle()
        keepScreenshot(named: "94-my-posts-post")
        back.tap()
        XCTAssertTrue(
            app.buttons["wall.filter.cheatMeal"].waitForExistence(timeout: 30), "返回 didn't go back to the wall")

        app.buttons["wall.filter.cheatMeal"].tap()
        let empty = app.descendants(matching: .any).matching(identifier: "wall.empty").firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 30), "an empty kind says nothing")
        settle()
        keepScreenshot(named: "93-my-posts-empty-kind")

        app.buttons["wall.back"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 30), "返回 didn't go back to 我")
    }

    func testSettingsAndDeleteAccount() {
        let app = launch(language: "zh-Hans")
        let settingsButton = app.buttons["me.settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 30), "我 never showed")
        settingsButton.tap()
        let settings = app.descendants(matching: .any).matching(identifier: "settings.page").firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 30), "设置 never opened")
        XCTAssertTrue(app.buttons["me.squad"].label.contains("周三不练腿俱乐部"), "no 我的小队 row with the squad")
        XCTAssertTrue(app.buttons["me.privacy"].exists, "no 隐私政策 row")
        let notifications = app.switches["me.notifications"]
        XCTAssertEqual(notifications.value as? String, "1")
        notifications.tap()
        waitFor(notifications, "value == '0'", "the notification switch didn't turn off")
        settle()
        keepScreenshot(named: "42-settings")

        app.swipeUp()
        assertClearOfTabBar(app.buttons["me.deleteAccount"], in: app)
        settle()
        keepScreenshot(named: "43-settings-bottom")

        // 退出登录 asks first; the in-memory member has nothing to sign out of, so 设置 stays.
        app.buttons["me.signOut"].tap()
        // The system sheet nests the button, so the identifier matches twice.
        let signOut = app.buttons.matching(identifier: "me.signOut.confirm").firstMatch
        XCTAssertTrue(signOut.waitForExistence(timeout: 30), "退出登录 didn't ask first")
        signOut.tap()
        waitFor(signOut, "exists == false", "the sign-out confirm stayed open")

        app.buttons["me.deleteAccount"].tap()
        let delete = app.descendants(matching: .any).matching(identifier: "delete.page").firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 30), "the 注销账号 page never opened")
        XCTAssertTrue(app.staticTexts["你会离开周三不练腿俱乐部"].exists)
        XCTAssertTrue(app.staticTexts["给 AI 的同意也一起撤回"].exists)
        XCTAssertFalse(app.buttons["tab.me"].exists, "the tab bar stayed over the 注销账号 page")
        let lastLine = app.staticTexts["删了就找不回来了。"]
        XCTAssertLessThanOrEqual(
            lastLine.frame.maxY, app.buttons["delete.cancel"].frame.minY, "the buttons cover what is deleted")
        settle()
        keepScreenshot(named: "44-delete-account")

        app.buttons["delete.cancel"].tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 30), "先不注销 didn't go back to 设置")
        XCTAssertTrue(app.buttons["tab.me"].waitForExistence(timeout: 30), "the tab bar didn't come back")

        app.buttons["me.deleteAccount"].tap()
        let confirm = app.buttons["delete.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 30))
        confirm.tap()
        // The in-memory member has nothing to sign out of, so the page stays, done.
        waitFor(confirm, "isEnabled == false", "the confirm button still takes taps after deleting")
    }

    /// The member picks their card's number in 设置, and the card wears it.
    func testJerseyNumber() {
        let app = launch(language: "zh-Hans")
        let settingsButton = app.buttons["me.settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 30), "我 never showed")
        settingsButton.tap()
        let row = app.buttons["me.jerseyNumber"]
        XCTAssertTrue(row.waitForExistence(timeout: 30), "no 球衣号码 row")
        XCTAssertTrue(row.label.contains("22"), "the row doesn't show the number: \(row.label)")
        row.tap()
        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 30), "the number page never opened")
        wheel.adjust(toPickerWheelValue: "07")
        assertClearOfTabBar(app.buttons["number.save"], in: app)
        settle()
        keepScreenshot(named: "49-jersey-number")
        app.buttons["number.save"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 30), "saving didn't go back to 设置")
        waitFor(row, "label CONTAINS '07'", "the row doesn't show the new number")
        app.buttons["settings.back"].tap()
        let card = app.buttons["me.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        XCTAssertTrue(card.label.contains("07号"), "the card doesn't wear the new number: \(card.label)")
    }

    /// A change that can't be saved flips back and says so; a delete that fails can be tried again.
    func testFailuresSayWhatHappened() {
        let app = launch(language: "zh-Hans", extra: ["-uitest-me-fails"])
        let settingsButton = app.buttons["me.settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 30))
        settingsButton.tap()
        let notifications = app.switches["me.notifications"]
        XCTAssertTrue(notifications.waitForExistence(timeout: 30))
        notifications.tap()
        XCTAssertTrue(app.staticTexts["me.saveFailed"].waitForExistence(timeout: 30), "no line saying it didn't save")
        waitFor(notifications, "value == '1'", "the switch didn't flip back")

        app.swipeUp()
        app.buttons["me.deleteAccount"].tap()
        let confirm = app.buttons["delete.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 30))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["delete.failed"].waitForExistence(timeout: 30), "no line saying it failed")
        XCTAssertTrue(confirm.isEnabled, "the confirm button can't be tried again")
        settle()
        keepScreenshot(named: "45-delete-account-failed")
    }

    func testMePageInEnglish() {
        let app = launch(language: "en")
        let card = app.buttons["me.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        XCTAssertTrue(card.label.contains("Workouts"), "the card isn't in English: \(card.label)")
        XCTAssertTrue(app.buttons["Edit your Wildcard athlete"].exists)
        XCTAssertTrue(app.buttons["tab.me"].label.contains("Me"))
        settle()
        keepScreenshot(named: "46-me-en")
        card.tap()
        waitFor(card, "label CONTAINS 'Cheat meals'", "the back isn't in English")
        settle()
        keepScreenshot(named: "47-me-card-back-en")
        app.buttons["me.settings"].tap()
        XCTAssertTrue(app.buttons["me.signOut"].waitForExistence(timeout: 30))
        settle()
        keepScreenshot(named: "48-settings-en")
    }

    /// What must stay tappable sits above the floating tab bar.
    private func assertClearOfTabBar(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 30), "\(element) never showed")
        let bar = tabButton("tab.today", in: app).frame
        XCTAssertLessThanOrEqual(element.frame.maxY, bar.minY, "\(element) sits under the tab bar")
    }

    /// 我 in Traditional Chinese reads in Taiwan's words, not converted ones.
    func testMePageInTraditionalChinese() {
        let app = launch(language: "zh-Hant")
        let card = app.buttons["me.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        XCTAssertTrue(card.label.contains("練了"), "the card isn't in Traditional Chinese: \(card.label)")
        XCTAssertTrue(app.buttons["編輯外卡運動員"].exists)
        settle()
        keepScreenshot(named: "49-me-zh-hant")
        app.buttons["me.settings"].tap()
        let language = app.buttons["me.language"]
        XCTAssertTrue(language.waitForExistence(timeout: 30), "設定 has no 語言 row")
        XCTAssertTrue(language.label.contains("繁體中文"), "the row doesn't name the language: \(language.label)")
        app.swipeUp()
        let deleteAccount = app.buttons["me.deleteAccount"]
        XCTAssertTrue(deleteAccount.waitForExistence(timeout: 30), "no delete-account row in 設定")
        XCTAssertTrue(deleteAccount.label.contains("刪除帳號"), "the row reads \(deleteAccount.label)")
        settle()
        keepScreenshot(named: "50-settings-zh-hant")
    }

    private func launch(language: String, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments +=
            ["-tab", "me", "-AppleLanguages", "(\(language))", "-AppleLocale", language, "-uitest-no-push"] + extra
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        return app
    }

    /// The character's idle and springs settle before a screenshot.
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
