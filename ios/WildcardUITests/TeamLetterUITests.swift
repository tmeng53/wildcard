import XCTest

/// A letter from the team (感谢信) on the sample squad: it flies in sealed over 今天; a tap on the
/// seal opens it, with the member's name, its lines, the badge and piece the team gave and
/// 立刻穿上 and 一会儿再说, whole on screen; 立刻穿上 opens 衣橱 wearing the piece. Screenshots of
/// each are kept for review beside the approved mockup.
@MainActor
final class TeamLetterUITests: XCTestCase {
    /// Slow CI simulators can take many seconds to show a screen; a real failure still fails.
    private static let wait: TimeInterval = 30

    func testTheLetterOpensAndWearsWhatItGave() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon",
            "-today.cardPage", "0", "-uitest-broadcast", "thanks",
        ]
        app.launch()

        let seal = app.descendants(matching: .any).matching(identifier: "today.letter.seal").firstMatch
        XCTAssertTrue(seal.waitForExistence(timeout: Self.wait), "the letter never flew in")
        // Never the banner as well.
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "notice.banner").firstMatch.exists)
        Thread.sleep(forTimeInterval: 1.5)
        keepScreenshot(named: "144-team-letter-sealed")

        seal.tap()
        let wear = app.buttons["today.teamLetter.wear"]
        XCTAssertTrue(wear.waitForExistence(timeout: Self.wait), "the letter has no 立刻穿上")
        // The letter unfolds and its buttons come in.
        Thread.sleep(forTimeInterval: 2)
        let letter = app.descendants(matching: .any).matching(identifier: "today.teamLetter").firstMatch
        let presents = app.descendants(matching: .any).matching(identifier: "today.teamLetter.presents").firstMatch
        let later = app.buttons["today.teamLetter.later"]
        XCTAssertTrue(presents.exists, "the letter draws nothing the team gave")
        XCTAssertTrue(app.staticTexts["点子王"].exists, "the badge has no name")
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(letter.frame), "the letter runs off the screen: \(letter.frame)")
        for part in [presents, wear, later] {
            XCTAssertTrue(letter.frame.contains(part.frame), "\(part) sticks out of the letter: \(part.frame)")
        }
        XCTAssertLessThan(presents.frame.maxY, wear.frame.minY + 1, "立刻穿上 isn't under the presents")
        keepScreenshot(named: "145-team-letter-open")

        wear.tap()
        let editor = app.descendants(matching: .any).matching(identifier: "editor.stage").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: Self.wait), "立刻穿上 didn't open 衣橱")
        XCTAssertFalse(letter.exists, "the letter stayed up over 衣橱")
        keepScreenshot(named: "146-team-letter-worn")
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
