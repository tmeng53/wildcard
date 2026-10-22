import XCTest

/// 我 the way a member uses it, on the in-memory member: the page, the notification switch, the
/// tabs and the 注销账号 page. Keeps screenshots for review.
@MainActor
final class MeUITests: XCTestCase {
    func testMePageAndDeleteAccount() {
        let app = launch(language: "zh-Hans")
        let page = app.descendants(matching: .any).matching(identifier: "me.page").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 30), "我 never showed")
        XCTAssertEqual(app.staticTexts["me.nickname"].label, "小林")
        XCTAssertEqual(app.staticTexts["me.trainedDays"].label, "128")
        XCTAssertTrue(app.buttons["me.squad"].label.contains("周三不练腿俱乐部"), "no 我的小队 row with the squad")
        XCTAssertTrue(app.buttons["tab.me"].isSelected, "the 我 tab isn't the selected one")
        settle()
        keepScreenshot(named: "40-me")

        let notifications = app.switches["me.notifications"]
        XCTAssertEqual(notifications.value as? String, "1")
        notifications.tap()
        waitFor(notifications, "value == '0'", "the notification switch didn't turn off")

        app.swipeUp()
        settle()
        keepScreenshot(named: "41-me-bottom")

        // 退出登录 asks first; the in-memory member has nothing to sign out of, so 我 stays.
        app.buttons["me.signOut"].tap()
        let signOut = app.buttons["me.signOut.confirm"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 30), "退出登录 didn't ask first")
        signOut.tap()
        waitFor(signOut, "exists == false", "the sign-out confirm stayed open")

        app.buttons["me.deleteAccount"].tap()
        let delete = app.descendants(matching: .any).matching(identifier: "delete.page").firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 30), "the 注销账号 page never opened")
        XCTAssertTrue(app.staticTexts["你会离开周三不练腿俱乐部"].exists)
        XCTAssertTrue(app.staticTexts["给 AI 的同意也一起撤回"].exists)
        settle()
        keepScreenshot(named: "42-delete-account")

        app.buttons["delete.cancel"].tap()
        XCTAssertTrue(page.waitForExistence(timeout: 30), "先不注销 didn't go back to 我")

        app.buttons["me.deleteAccount"].tap()
        let confirm = app.buttons["delete.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 30))
        confirm.tap()
        waitFor(confirm, "isEnabled == false", "the confirm button still takes taps after deleting")

        app.buttons["tab.today"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "today.card").firstMatch.waitForExistence(timeout: 30),
            "the 今天 tab didn't open")
    }

    /// A change that can't be saved flips back and says so; a delete that fails can be tried again.
    func testFailuresSayWhatHappened() {
        let app = launch(language: "zh-Hans", extra: ["-uitest-me-fails"])
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
        keepScreenshot(named: "43-delete-account-failed")
    }

    func testMePageInEnglish() {
        let app = launch(language: "en")
        XCTAssertTrue(app.staticTexts["me.nickname"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["Edit character"].exists)
        XCTAssertTrue(app.buttons["tab.me"].label.contains("Me"))
        settle()
        keepScreenshot(named: "44-me-en")
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
