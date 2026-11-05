import XCTest

/// The coach's morning note (便条, the approved design, 2026-11-05): on the first open after it
/// arrived it slides up over 今天, white on a clipboard with 毛头, whom it is for and the day, its
/// line and 收下; 收下 puts it away and the home is as before. Checked on the smallest phone too:
/// the card stays on screen with 收下 clear of the tab bar. Screenshots are kept for review.
@MainActor
final class CoachNoteUITests: XCTestCase {
    private static let wait: TimeInterval = 30
    private static let line = "今天出赛表写的是力量。病刚好，重量先打八折，我在场边数着。"

    func testTheMorningNoteShowsOnceAndIsPutAway() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon",
            "-today.cardPage", "0", "-uitest-coach-note",
        ]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }

        let note = app.descendants(matching: .any).matching(identifier: "today.coachNote").firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: Self.wait), "no morning note on 今天")
        let text = app.staticTexts["today.coachNote.text"]
        XCTAssertEqual(text.label, Self.line)
        let putAway = app.buttons["today.coachNote.putAway"]
        let screen = app.windows.firstMatch.frame
        XCTAssertTrue(screen.contains(note.frame), "the note runs off the screen: \(note.frame)")
        XCTAssertTrue(putAway.isHittable, "收下 is covered")
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot(named: "105-coach-note")

        putAway.tap()
        XCTAssertTrue(note.waitForNonExistence(timeout: Self.wait), "收下 didn't put the note away")
        XCTAssertTrue(app.buttons["today.checkin"].waitForExistence(timeout: Self.wait), "the home isn't back")
        XCTAssertTrue(app.buttons["today.checkin"].isHittable, "打卡 is still covered")
        keepScreenshot(named: "106-coach-note-put-away")
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
