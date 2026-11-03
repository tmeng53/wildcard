import XCTest

/// The coach on 动态, the way a member meets it: today's 战术板 pinned at the top of today, 毛头's
/// word under the run with the 教练 tag, its 🔥 first among the run's reactions and first in who
/// reacted, its word first on the run's own page, and replying to it there the way one replies to a
/// teammate, with its answer showing under the reply. Screenshots are kept for review.
@MainActor
final class CoachFeedUITests: XCTestCase {
    /// Slow CI simulators can take many seconds to show a screen; a real failure still fails.
    private static let wait: TimeInterval = 30
    private static let maxSwipes = 4

    func testCoachOnTheFeed() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon", "-tab",
            "feed", "-uitest-coach",
        ]
        app.launch()

        let board = element("feed.coachBoard", in: app)
        XCTAssertTrue(board.waitForExistence(timeout: Self.wait), "no 战术板 on today")
        XCTAssertTrue(board.label.contains("教练 毛头"), "the 战术板 doesn't name the coach: \(board.label)")
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(board.frame), "the 战术板 is cut off: \(board.frame)")
        let title = app.staticTexts["feed.title"]
        XCTAssertGreaterThanOrEqual(board.frame.minY, title.frame.maxY, "the 战术板 is over the title")
        Thread.sleep(forTimeInterval: 0.8)
        keepScreenshot(named: "63-coach-feed-board")

        // 毛头's word under the run, on its card.
        let word = app.buttons.matching(identifier: "feed.comments")
            .matching(NSPredicate(format: "label BEGINSWITH '教练 毛头：'")).firstMatch
        let feed = app.scrollViews.firstMatch
        var swipes = 0
        while swipes < Self.maxSwipes, !(word.exists && word.isHittable) {
            feed.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(word.exists, "no coach word under a post")
        XCTAssertTrue(word.label.hasPrefix("教练 毛头："), "the coach's word has no 教练 tag: \(word.label)")
        Thread.sleep(forTimeInterval: 0.8)
        keepScreenshot(named: "64-coach-feed-comment")

        // Its 🔥 is first among the run's reactions, and first in who reacted.
        let reactions = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '教练 毛头：🔥'")).firstMatch
        XCTAssertTrue(reactions.waitForExistence(timeout: Self.wait), "the coach's 🔥 isn't on the run")
        reactions.tap()
        let coachRow = element("feed.whoCoach", in: app)
        XCTAssertTrue(coachRow.waitForExistence(timeout: Self.wait), "who reacted doesn't list the coach")
        XCTAssertTrue(window.contains(coachRow.frame), "the coach's row is cut off: \(coachRow.frame)")
        Thread.sleep(forTimeInterval: 0.8)
        keepScreenshot(named: "65-coach-feed-who")
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()

        // On the run's own page, the coach's word comes first among the comments.
        word.tap()
        let row = element("post.coachComment", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: Self.wait), "the post's page has no coach word")
        let comments = app.descendants(matching: .any).matching(identifier: "post.comment")
        XCTAssertGreaterThan(comments.count, 0, "the run's comments are missing")
        XCTAssertLessThan(row.frame.minY, comments.element(boundBy: 0).frame.minY, "the coach's word isn't first")
        Thread.sleep(forTimeInterval: 0.8)
        keepScreenshot(named: "66-coach-post-page")
        replyToTheCoach(row, under: comments, in: app)
    }

    /// Replying to 毛头 is replying to a teammate: tap his word, write, send, and he answers.
    private func replyToTheCoach(_ row: XCUIElement, under comments: XCUIElementQuery, in app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        row.tap()
        XCTAssertTrue(app.buttons["post.cancelReply"].waitForExistence(timeout: Self.wait), "tapping didn't reply")
        XCTAssertTrue(app.staticTexts["回复 毛头"].exists, "the box doesn't say whom it replies to")
        let box = element("post.field", in: app)
        box.typeText("教练你也跑")
        let send = app.buttons["post.send"]
        XCTAssertTrue(window.contains(send.frame), "the send button is cut off: \(send.frame)")
        Thread.sleep(forTimeInterval: 0.8)
        keepScreenshot(named: "66-coach-post-replying")
        send.tap()
        let answer = element("post.coachAnswer", in: app)
        XCTAssertTrue(answer.waitForExistence(timeout: Self.wait), "the coach didn't answer the reply")
        XCTAssertTrue(answer.label.hasPrefix("教练 毛头 回复 "), "the answer has no 教练 tag: \(answer.label)")
        XCTAssertFalse(app.buttons["post.cancelReply"].exists, "still replying after sending")
        let reply = comments.matching(NSPredicate(format: "label CONTAINS '教练你也跑'")).firstMatch
        XCTAssertTrue(reply.exists, "the reply to the coach isn't on the page")
        XCTAssertLessThan(reply.frame.minY, answer.frame.minY, "the answer isn't under the reply")
        XCTAssertTrue(window.contains(answer.frame), "the answer is cut off: \(answer.frame)")
        Thread.sleep(forTimeInterval: 0.8)
        keepScreenshot(named: "66-coach-post-answer")
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
