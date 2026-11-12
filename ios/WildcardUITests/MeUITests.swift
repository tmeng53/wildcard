import XCTest

/// 我 the way a member uses it, on the in-memory member: the player card and its back, 球衣号码
/// from the character editor,
/// 出赛表 opened inside 我, 设置 with the notification switch, and the 注销账号 page. Keeps screenshots for review.
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
        XCTAssertFalse(card.label.contains("SINCE"), "the card still shows a join year: \(card.label)")
        XCTAssertTrue(card.label.contains("早八战神"), "the card doesn't wear the latest title: \(card.label)")
        XCTAssertTrue(card.label.contains("徽章"), "the card has no 徽章 count: \(card.label)")
        XCTAssertTrue(tabButton("tab.me", in: app).isSelected, "the 我 tab isn't the selected one")
        assertClearOfTabBar(app.buttons["me.editCharacter"], in: app)
        settle()
        keepScreenshot(named: "40-me")

        // A tap turns the card over to the career line and the badge board; a tap off the badges
        // turns it back.
        card.tap()
        let back = app.descendants(matching: .any).matching(identifier: "me.cardBack").firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "the card didn't turn over")
        let badges = app.buttons.matching(identifier: "me.badge")
        XCTAssertEqual(badges.count, 7, "the board doesn't show the seven titles")
        settle()
        keepScreenshot(named: "41-me-card-back")
        back.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the card didn't turn back")
    }

    /// 我的动态 from 我: the member's own posts as a wall under its month, the header's counts, a
    /// kind with nothing in it, and back to 我.
    func testMyPostsWall() {
        let app = launch(language: "zh-Hans")
        let entry = app.buttons["me.myPosts"]
        XCTAssertTrue(entry.waitForExistence(timeout: 30), "我 has no 我的动态 tile")
        // The tiles sit under the card, which spans the page: scroll them clear of the tab bar.
        app.swipeUp()
        assertClearOfTabBar(entry, in: app)
        waitFor(entry, "label CONTAINS '我的动态'", "the tile isn't 我的动态")
        settle()
        keepScreenshot(named: "40-me-tiles")
        entry.tap()
        let wall = app.descendants(matching: .any).matching(identifier: "wall.page").firstMatch
        XCTAssertTrue(wall.waitForExistence(timeout: 30), "我的动态 never opened")
        let tile = app.descendants(matching: .any).matching(identifier: "wall.tile").firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 30), "the wall has no tiles")
        XCTAssertTrue(
            app.staticTexts["wall.counts"].label.contains("发过 2 条"),
            "the header has no counts: \(app.staticTexts["wall.counts"].label)")
        XCTAssertTrue(tile.frame.maxX <= app.frame.maxX && tile.frame.minX >= 0, "a tile runs off the screen")
        // The newest, this morning's run, was only recorded: its tile says so in words.
        XCTAssertTrue(tile.label.contains("未发动态"), "the unposted run's tile doesn't say 未发动态: \(tile.label)")
        settle()
        keepScreenshot(named: "92-my-posts")

        // A tile opens 动态's own post page, without the tab bar, and 返回 comes back to the wall.
        tile.tap()
        let back = backButton(in: app)
        XCTAssertTrue(back.waitForExistence(timeout: 30), "a tile didn't open the post's page")
        let unposted = app.descendants(matching: .any).matching(identifier: "post.unposted").firstMatch
        XCTAssertTrue(unposted.waitForExistence(timeout: 10), "the unposted run's page doesn't say 未发动态")
        XCTAssertTrue(unposted.frame.maxX <= app.frame.maxX, "未发动态 runs off the screen")
        waitFor(
            app.tabBars.firstMatch, "exists == false OR hittable == false", "the tab bar stayed over the post's page")
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

        backButton(in: app).tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 30), "返回 didn't go back to 我")
    }

    func testSettingsAndDeleteAccount() {
        let app = launch(language: "zh-Hans")
        let settingsButton = app.buttons["me.settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 30), "我 never showed")
        settingsButton.tap()
        let settings = app.descendants(matching: .any).matching(identifier: "settings.page").firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 30), "设置 never opened")
        XCTAssertTrue(app.buttons["me.privacy"].exists, "no 隐私政策 row")
        // 设置 holds only the app's own settings: the squad and the week live elsewhere.
        for moved in ["me.squad", "me.weeklyTemplate"] {
            XCTAssertFalse(app.buttons[moved].exists, "\(moved) is still in 设置")
        }
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
        let signOut = app.buttons.matching(identifier: "me.signOut.confirm").firstMatch
        XCTAssertTrue(signOut.waitForExistence(timeout: 30), "退出登录 didn't ask first")
        signOut.tap()
        waitFor(signOut, "exists == false", "the sign-out confirm stayed open")

        app.buttons["me.deleteAccount"].tap()
        let delete = app.descendants(matching: .any).matching(identifier: "delete.page").firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 30), "the 注销账号 page never opened")
        XCTAssertTrue(app.staticTexts["你会离开周三不练腿俱乐部"].exists)
        XCTAssertTrue(app.staticTexts["给 AI 的同意也一起撤回"].exists)
        waitFor(
            app.tabBars.firstMatch, "exists == false OR hittable == false", "the tab bar stayed over the 注销账号 page")
        let lastLine = app.staticTexts["删了就找不回来了。"]
        XCTAssertLessThanOrEqual(
            lastLine.frame.maxY, app.buttons["delete.cancel"].frame.minY, "the buttons cover what is deleted")
        settle()
        keepScreenshot(named: "44-delete-account")

        app.buttons["delete.cancel"].tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 30), "先不注销 didn't go back to 设置")
        XCTAssertTrue(tabButton("tab.me", in: app).waitForExistence(timeout: 30), "the tab bar didn't come back")

        app.buttons["me.deleteAccount"].tap()
        let confirm = app.buttons["delete.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 30))
        confirm.tap()
        // The in-memory member has nothing to sign out of, so the page stays, done.
        waitFor(confirm, "isEnabled == false", "the confirm button still takes taps after deleting")
    }

    /// The member picks their card's number from the character editor, and the card wears it;
    /// 设置 no longer has it.
    func testJerseyNumber() {
        let app = launch(language: "zh-Hans")
        let edit = app.buttons["me.editCharacter"]
        XCTAssertTrue(edit.waitForExistence(timeout: 30), "我 never showed")
        edit.tap()
        let entry = app.buttons["editor.jerseyNumber"]
        XCTAssertTrue(entry.waitForExistence(timeout: 30), "the editor has no 球衣号码")
        XCTAssertTrue(entry.label.contains("22"), "the editor doesn't show the number: \(entry.label)")
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(entry.frame), "球衣号码 runs off the screen: \(entry.frame)")
        settle()
        keepScreenshot(named: "48-editor-jersey-number")
        entry.tap()
        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 30), "the number page never opened")
        wheel.adjust(toPickerWheelValue: "07")
        XCTAssertTrue(window.contains(app.buttons["number.save"].frame), "保存 runs off the screen")
        settle()
        keepScreenshot(named: "49-jersey-number")
        app.buttons["number.save"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 30), "saving didn't go back to the editor")
        waitFor(entry, "label CONTAINS '07'", "the editor doesn't show the new number")
        app.buttons["editor.cancel"].tap()
        let card = app.buttons["me.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        XCTAssertTrue(card.label.contains("07号"), "the card doesn't wear the new number: \(card.label)")
        app.buttons["me.settings"].tap()
        XCTAssertTrue(backButton(in: app).waitForExistence(timeout: 30), "设置 never opened")
        XCTAssertFalse(app.buttons["me.jerseyNumber"].exists, "设置 still has 球衣号码")
    }

    /// 出赛表 opens inside 我 from the tile under the card, with this week's number and count, and its
    /// 我的每周计划 is one of its own chips; 返回 goes back to 我 with the tab bar there all along.
    func testScheduleOpensInsideMe() {
        let app = launch(language: "zh-Hans")
        let row = app.buttons["me.schedule"]
        XCTAssertTrue(row.waitForExistence(timeout: 30), "no 出赛表 tile on 我")
        XCTAssertTrue(row.label.contains("这周还有 4 天"), "the tile doesn't count the days left: \(row.label)")
        XCTAssertTrue(row.label.contains("W3"), "the tile doesn't number this week: \(row.label)")
        app.swipeUp()
        assertClearOfTabBar(row, in: app)
        row.tap()
        XCTAssertTrue(app.buttons["schedule.save"].waitForExistence(timeout: 30), "出赛表 didn't open")
        XCTAssertTrue(tabButton("tab.me", in: app).isSelected, "出赛表 left 我")
        app.buttons["schedule.template"].tap()
        let note = app.descendants(matching: .any)["schedule.template.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 30), "the 我的每周计划 chip didn't open the template")
        settle()
        keepScreenshot(named: "48-me-schedule-template")
        backButton(in: app).tap()
        XCTAssertTrue(row.waitForExistence(timeout: 30), "返回 didn't go back to 我")
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
        XCTAssertEqual(app.buttons["me.editCharacter"].label, "Dress up", "换装 isn't in English")
        XCTAssertTrue(tabButton("tab.me", in: app).label.contains("Me"))
        settle()
        keepScreenshot(named: "46-me-en")
        card.tap()
        XCTAssertTrue(app.staticTexts["Badges"].waitForExistence(timeout: 5), "the back isn't in English")
        XCTAssertTrue(app.staticTexts["Sunday reveal"].exists, "the next slot isn't in English")
        settle()
        keepScreenshot(named: "47-me-card-back-en")
        app.buttons["me.settings"].tap()
        XCTAssertTrue(app.buttons["me.signOut"].waitForExistence(timeout: 30))
        settle()
        keepScreenshot(named: "48-settings-en")
    }

    /// What must stay tappable sits above the floating tab bar.
    func assertClearOfTabBar(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 30), "\(element) never showed")
        let bar = tabButton("tab.today", in: app).frame
        XCTAssertLessThanOrEqual(element.frame.maxY, bar.minY, "\(element) sits under the tab bar")
    }

    /// 我 in Traditional Chinese reads in Taiwan's words, not converted ones.
    func testMePageInTraditionalChinese() {
        let app = launch(language: "zh-Hant")
        let card = app.buttons["me.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        XCTAssertTrue(card.label.contains("訓練"), "the card isn't in Traditional Chinese: \(card.label)")
        XCTAssertEqual(app.buttons["me.editCharacter"].label, "換裝")
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

    func launch(language: String, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments +=
            ["-tab", "me", "-AppleLanguages", "(\(language))", "-AppleLocale", language, "-uitest-no-push"] + extra
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        return app
    }

    /// The character's idle and springs settle before a screenshot.
    func settle() {
        Thread.sleep(forTimeInterval: 1)
    }

    func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// 意见反馈, apart from the class so its body stays short.
extension MeUITests {
    /// 意见反馈 is 关于's first row: write a problem, send it, see the check and go back to 设置.
    func testFeedback() {
        let app = launch(language: "zh-Hans")
        let settingsButton = app.buttons["me.settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 30), "我 never showed")
        settingsButton.tap()
        let settings = app.descendants(matching: .any).matching(identifier: "settings.page").firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 30), "设置 never opened")
        let row = app.buttons["me.feedback"]
        if !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 30), "设置 has no 意见反馈")
        row.tap()

        let page = app.descendants(matching: .any).matching(identifier: "feedback.page").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 30), "意见反馈 never opened")
        XCTAssertTrue(app.buttons["feedback.review"].exists, "写评价 is missing")
        XCTAssertFalse(app.buttons["feedback.send"].isEnabled, "发送 works with nothing written")
        settle()
        keepScreenshot(named: "95-feedback")

        let text = app.textViews["feedback.text"]
        text.tap()
        text.typeText("照片一直在转圈")
        XCTAssertTrue(app.buttons["feedback.send"].isEnabled, "发送 doesn't work once something is written")
        app.buttons["feedback.idea"].tap()
        settle()
        keepScreenshot(named: "96-feedback-written")

        app.buttons["feedback.send"].tap()
        let sent = app.descendants(matching: .any).matching(identifier: "feedback.sent").firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 30), "sending never said thanks")
        XCTAssertTrue(app.staticTexts["谢谢你的反馈"].waitForExistence(timeout: 5))
        settle()
        keepScreenshot(named: "97-feedback-sent")
        XCTAssertTrue(settings.waitForExistence(timeout: 30), "the page didn't go back to 设置 by itself")
    }
}
