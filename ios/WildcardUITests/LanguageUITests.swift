import XCTest

/// The app's language: Simplified Chinese from the first launch, whatever the phone is set to,
/// until the member picks another in the app, which then speaks it at once.
@MainActor
final class LanguageUITests: XCTestCase {
    /// How long a check waits for the UI on a busy CI runner.
    private static let wait: TimeInterval = 30

    /// A new install on a phone set to English opens in Chinese from its first launch, sign-up's:
    /// SwiftUI's text, the strings the code looks up (the squad's suggested name) and the
    /// formatted dates alike. The simulator is English, as CI's is, and no language is passed.
    func testFirstLaunchOnAnEnglishPhoneIsChinese() {
        let app = launchFirstTime(["-onboarding", "-uitest-monday"])
        let signIn = app.buttons["signup.signIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: Self.wait), "the open screen never appeared")
        XCTAssertEqual(signIn.label, "通过 Apple 继续")
        XCTAssertTrue(app.links["用户协议"].exists, "the terms line isn't in Chinese")
        XCTAssertTrue(app.links["隐私政策"].exists, "the privacy policy link isn't in Chinese")
        // The globe that picks the language sits in the top corner, whole and on screen.
        let globe = app.buttons["signup.language"]
        XCTAssertEqual(globe.label, "语言")
        XCTAssertTrue(app.windows.firstMatch.frame.contains(globe.frame), "the language button is off screen")
        settle()
        keepScreenshot(named: "51-first-launch-open")
        signIn.tap()
        let editorDone = app.buttons["editor.done"]
        XCTAssertTrue(editorDone.waitForExistence(timeout: Self.wait), "角色和昵称 never appeared")
        let nickname = app.textFields["editor.nickname"]
        nickname.tap()
        nickname.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12))
        nickname.typeText("Tracy\n")
        waitFor(editorDone, "isEnabled == true", "确认 stays off with a nickname")
        editorDone.tap()
        let squadDone = app.buttons["squad.done"]
        XCTAssertTrue(squadDone.waitForExistence(timeout: Self.wait), "你的小队 never appeared")
        XCTAssertEqual(app.textFields["squad.name"].value as? String, "Tracy 的小队")
        settle()
        keepScreenshot(named: "52-first-launch-squad")
        waitFor(squadDone, "isEnabled == true", "建小队 stays off with a name")
        squadDone.tap()
        let skipSports = app.buttons["sports.skip"]
        XCTAssertTrue(skipSports.waitForExistence(timeout: Self.wait), "平时练什么？ never appeared")
        XCTAssertTrue(app.buttons["sports.run"].label.contains("跑步"), "a sport isn't in Chinese")
        skipSports.tap()
        let monday = app.buttons["week.day.0"]
        XCTAssertTrue(monday.waitForExistence(timeout: Self.wait), "本周目标 never appeared")
        XCTAssertTrue(monday.label.contains("周一"), "the week's days aren't in Chinese: \(monday.label)")
        settle()
        keepScreenshot(named: "53-first-launch-week")
    }

    /// The open screen's globe switches the whole app to English before signing up: the
    /// screen's words, the sign-in button, the squad's suggested name, a sport and the week's days.
    func testTheGlobeSwitchesToEnglishAtOnce() {
        let app = launchFirstTime(["-onboarding", "-uitest-monday"])
        let globe = app.buttons["signup.language"]
        XCTAssertTrue(globe.waitForExistence(timeout: Self.wait), "the open screen has no globe")
        globe.tap()
        let english = app.buttons["English"]
        XCTAssertTrue(english.waitForExistence(timeout: Self.wait), "the language sheet has no English")
        settle()
        keepScreenshot(named: "54-language-sheet")
        english.tap()
        let signIn = app.buttons["signup.signIn"]
        waitFor(signIn, "label == 'Continue with Apple'", "the sign-in button stayed Chinese")
        XCTAssertTrue(app.links["Terms"].exists, "the terms line stayed Chinese")
        settle()
        keepScreenshot(named: "55-open-en")
        signIn.tap()
        let editorDone = app.buttons["editor.done"]
        XCTAssertTrue(editorDone.waitForExistence(timeout: Self.wait), "the editor never appeared")
        let nickname = app.textFields["editor.nickname"]
        nickname.tap()
        nickname.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12))
        nickname.typeText("Tracy\n")
        waitFor(editorDone, "isEnabled == true", "Done stays off with a nickname")
        editorDone.tap()
        let squadDone = app.buttons["squad.done"]
        XCTAssertTrue(squadDone.waitForExistence(timeout: Self.wait), "the squad step never appeared")
        XCTAssertEqual(app.textFields["squad.name"].value as? String, "Tracy's squad")
        waitFor(squadDone, "isEnabled == true", "Start squad stays off with a name")
        squadDone.tap()
        let skipSports = app.buttons["sports.skip"]
        XCTAssertTrue(skipSports.waitForExistence(timeout: Self.wait), "the sports step never appeared")
        XCTAssertTrue(app.buttons["sports.run"].label.contains("Run"), "a sport stayed Chinese")
        skipSports.tap()
        let monday = app.buttons["week.day.0"]
        XCTAssertTrue(monday.waitForExistence(timeout: Self.wait), "the week step never appeared")
        XCTAssertTrue(monday.label.contains("Mon"), "the week's days stayed Chinese: \(monday.label)")
    }

    /// 设置's 语言 switches the app too, and back.
    func testSettingsSwitchesTheLanguage() {
        let app = launchFirstTime(["-tab", "me", "-uitest-no-push"])
        let settingsButton = app.buttons["me.settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: Self.wait), "我 never showed")
        settingsButton.tap()
        let row = app.buttons["me.language"]
        XCTAssertTrue(row.waitForExistence(timeout: Self.wait), "设置 has no 语言 row")
        XCTAssertTrue(row.label.contains("简体中文"), "the row doesn't name the language: \(row.label)")
        row.tap()
        let english = app.buttons["English"]
        XCTAssertTrue(english.waitForExistence(timeout: Self.wait), "the language sheet has no English")
        english.tap()
        XCTAssertTrue(app.buttons["tab.me"].waitForExistence(timeout: Self.wait), "the tabs went away")
        XCTAssertTrue(app.buttons["tab.me"].label.contains("Me"), "the tab bar stayed Chinese")
        settle()
        keepScreenshot(named: "56-me-en")
        if !app.buttons["me.language"].exists { app.buttons["me.settings"].tap() }
        let again = app.buttons["me.language"]
        XCTAssertTrue(again.waitForExistence(timeout: Self.wait), "Settings has no Language row")
        XCTAssertTrue(again.label.contains("English"), "the row doesn't name English: \(again.label)")
        again.tap()
        let chinese = app.buttons["简体中文"]
        XCTAssertTrue(chinese.waitForExistence(timeout: Self.wait), "the language sheet has no 简体中文")
        chinese.tap()
        XCTAssertTrue(app.buttons["tab.me"].waitForExistence(timeout: Self.wait), "the tabs went away")
        XCTAssertTrue(app.buttons["tab.me"].label.contains("我"), "the tab bar didn't go back to Chinese")
    }

    /// Launches as a new install would, with no language recorded and none passed.
    private func launchFirstTime(_ arguments: [String]) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += arguments + ["-uitest-first-launch"]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        return app
    }

    private func settle() {
        Thread.sleep(forTimeInterval: 2)
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
