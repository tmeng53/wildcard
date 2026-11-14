import XCTest

/// A card's comment button is for writing: on 动态 it opens the post's own page with the comment
/// box already taking the keyboard, and on that page it goes back to the box, to the post.
@MainActor
final class CommentButtonUITests: XCTestCase {
    /// Slow CI simulators can take many seconds to show a screen; a real failure still fails.
    private static let wait: TimeInterval = 30

    func testCommentButtonStartsAComment() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon", "-tab",
            "feed",
        ]
        app.launch()

        let comment = app.buttons.matching(identifier: "feed.comment").firstMatch
        XCTAssertTrue(comment.waitForExistence(timeout: Self.wait), "no card shows the comment button")
        comment.tap()

        let box = element("post.field", in: app)
        XCTAssertTrue(box.waitForExistence(timeout: Self.wait), "the comment button didn't open the post's page")
        assertTyping(in: box, "the post's page opened without the keyboard")
        box.typeText("冲")
        Thread.sleep(forTimeInterval: 0.5)
        keepScreenshot(named: "52-post-comment-button")

        // With the keyboard put away, the card's comment button on the page brings it back.
        app.scrollViews.firstMatch.swipeDown()
        waitFor(app.keyboards.firstMatch, "exists == false", "swiping down didn't put the keyboard away")
        app.buttons.matching(identifier: "feed.comment").firstMatch.tap()
        assertTyping(in: box, "the comment button on the post's page didn't bring the keyboard back")
    }

    /// The box has the keyboard a moment after the tap (when a tap outside would have put it away).
    private func assertTyping(in box: XCUIElement, _ message: String) {
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertEqual(box.value(forKey: "hasKeyboardFocus") as? Bool, true, message)
    }

    private func waitFor(_ element: XCUIElement, _ predicate: String, _ message: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: Self.wait), .completed, message)
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
