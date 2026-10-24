import XCTest

/// The app's language: Simplified Chinese from the first launch, whatever the phone is set to.
@MainActor
final class LanguageUITests: XCTestCase {
    /// How long a check waits for the UI on a busy CI runner.
    private static let wait: TimeInterval = 30

    /// A new install on a phone set to English opens in Chinese from its first launch, sign-up's:
    /// SwiftUI's text, the strings the code looks up (the squad's suggested name) and the
    /// formatted dates alike. The simulator is English, as CI's is, and no language is passed.
    func testFirstLaunchOnAnEnglishPhoneIsChinese() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-onboarding", "-uitest-monday", "-uitest-first-launch"]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        let signIn = app.buttons["signup.signIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: Self.wait), "the open screen never appeared")
        XCTAssertEqual(signIn.label, "通过 Apple 继续")
        settle()
        keepScreenshot(named: "51-first-launch-open")
        signIn.tap()
        let editorDone = app.buttons["editor.done"]
        XCTAssertTrue(editorDone.waitForExistence(timeout: Self.wait), "角色和昵称 never appeared")
        let nickname = app.textFields["editor.nickname"]
        nickname.tap()
        nickname.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12))
        nickname.typeText("Tracy\n")
        waitFor(editorDone, "isEnabled == true", "就这样 stays off with a nickname")
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
