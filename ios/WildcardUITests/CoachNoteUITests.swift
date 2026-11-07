import XCTest

/// The coach's morning note never slides up over 今天 by itself (Tracy, 2026-11-07): with a note
/// waiting, the home opens as usual, 打卡 is free, and the phone in 毛头's hand shows a dot and
/// buzzes (the approved 毛头的手机来消息). A tap on 毛头 opens the note, and 收下 puts it away and
/// takes the dot with it. It also opens from its row in 通知 (`NoticeBellUITests`) or its push.
/// Screenshots are kept for review.
@MainActor
final class CoachNoteUITests: XCTestCase {
    private static let wait: TimeInterval = 30

    func testAWaitingNoteShowsOnTheCoachsPhoneAndOpensFromIt() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon",
            "-today.cardPage", "0", "-uitest-coach-note",
        ]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }

        let checkIn = app.buttons["today.checkin"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: Self.wait), "the home didn't open")
        let coach = app.buttons["today.coach"]
        XCTAssertTrue(coach.waitForExistence(timeout: Self.wait), "毛头 isn't on the sideline")
        // Once the note has loaded, the coach's phone shows it.
        let unread = NSPredicate(format: "value == %@", "有新消息")
        expectation(for: unread, evaluatedWith: coach)
        waitForExpectations(timeout: Self.wait)
        let note = app.descendants(matching: .any).matching(identifier: "today.coachNote").firstMatch
        XCTAssertFalse(note.exists, "the morning note slid up by itself")
        XCTAssertTrue(checkIn.isHittable, "打卡 is covered")
        keepScreenshot(named: "105-coach-note-waiting")

        coach.tap()
        XCTAssertTrue(note.waitForExistence(timeout: Self.wait), "tapping 毛头 didn't open the note")
        // Once it has grown out of the coach.
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot(named: "106-coach-note-opened")

        app.buttons["today.coachNote.putAway"].tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: note)
        waitForExpectations(timeout: Self.wait)
        XCTAssertNotEqual(coach.value as? String, "有新消息", "the dot stayed after 收下")
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
