import XCTest

/// 群聊 on the sample squad, the way a member uses it: the glass button beside 打卡 opens it, an
/// @ of 毛头 brings its dots and then its answer, and a long press lifts a message with the emoji
/// bar and the menu. Screenshots are kept to compare with the approved design.
@MainActor
final class ChatUITests: XCTestCase {
    /// Slow CI simulators can take many seconds to show a screen; a real failure still fails.
    private static let wait: TimeInterval = 30
    private static let answer = "前一天别练腿，留着周六用。"

    func testTheCoachAnswersAnAtAndAMessageLifts() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon",
            "-today.cardPage", "0", "-uitest-coach",
        ]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }

        let entry = app.buttons["home.chat"]
        XCTAssertTrue(entry.waitForExistence(timeout: Self.wait), "no 群聊 button beside 打卡")
        keepScreenshot(named: "70-chat-entry")
        entry.tap()

        let field = element("chat.field", in: app)
        XCTAssertTrue(field.waitForExistence(timeout: Self.wait), "the chat didn't open")
        XCTAssertTrue(labeled("周六谁去爬山？", in: app).waitForExistence(timeout: Self.wait), "no sample lines")
        XCTAssertFalse(app.tabBars.firstMatch.isHittable, "the tab bar shows over the chat")
        keepScreenshot(named: "71-chat")

        app.buttons["chat.mentionCoach"].tap()
        field.typeText("周六之前练啥")
        keepScreenshot(named: "72-chat-composing")
        app.buttons["chat.send"].tap()
        XCTAssertTrue(labeled(Self.answer, in: app).waitForExistence(timeout: Self.wait), "毛头 didn't answer the @")
        let bar = element("chat.send", in: app)
        XCTAssertTrue(
            app.windows.firstMatch.frame.contains(bar.frame), "the composer runs off the screen: \(bar.frame)")
        keepScreenshot(named: "73-chat-coach-answer")

        labeled(Self.answer, in: app).press(forDuration: 0.8)
        XCTAssertTrue(element("chat.menu.reply", in: app).waitForExistence(timeout: Self.wait), "no long-press menu")
        XCTAssertTrue(element("chat.emoji", in: app).exists, "no emoji bar over the lifted message")
        Thread.sleep(forTimeInterval: 0.6)
        keepScreenshot(named: "74-chat-lifted")
        element("chat.menu.reply", in: app).tap()
        XCTAssertTrue(element("chat.replying", in: app).waitForExistence(timeout: Self.wait), "回复 didn't quote it")
        keepScreenshot(named: "75-chat-replying")

        app.buttons["chat.back"].tap()
        XCTAssertTrue(app.buttons["today.checkin"].waitForExistence(timeout: Self.wait), "返回 didn't go home")
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Any element showing exactly `label`.
    private func labeled(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
