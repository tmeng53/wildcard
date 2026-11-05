import XCTest

/// The sample member's training has just opened DEUCE CLUB (or brought WARM-UP a new piece): 今天
/// drops the notice in, whole on screen and on one line each for its title and detail, and a tap
/// on it opens 我's character editor inside the store. Screenshots are kept for review.
@MainActor
final class UnlockNoticeUITests: XCTestCase {
    /// Slow CI simulators can take many seconds to show a screen; a real failure still fails.
    private static let wait: TimeInterval = 30

    func testAStoreThatOpenedIsToldAndATapWalksIn() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon",
            "-uitest-bubble-hold",
            "-today.cardPage", "0", "-uitest-unlocked",
        ]
        app.launch()

        let banner = app.descendants(matching: .any).matching(identifier: "notice.banner").firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: Self.wait), "the notice never dropped in")
        XCTAssertTrue(banner.label.contains("DEUCE CLUB 开门了"), "the notice says \(banner.label)")
        XCTAssertTrue(banner.label.contains("网球练满 3 次"), "the notice says \(banner.label)")
        // Lets the drop's spring settle.
        Thread.sleep(forTimeInterval: 0.6)
        keepScreenshot(named: "96-notice-store-unlocked")

        let window = app.windows.firstMatch.frame
        let frame = banner.frame
        XCTAssertGreaterThanOrEqual(frame.minX, window.minX, "the notice runs off the left: \(frame)")
        XCTAssertLessThanOrEqual(frame.maxX, window.maxX, "the notice runs off the right: \(frame)")
        XCTAssertGreaterThanOrEqual(frame.minY, window.minY, "the notice runs off the top: \(frame)")
        // Two lines (title and detail) beside a 36-point icon: a wrapped one would make it taller.
        XCTAssertLessThan(frame.height, 90, "the notice wrapped: \(frame)")

        banner.tap()
        let back = app.descendants(matching: .any).matching(identifier: "editor.store.back").firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: Self.wait), "the tap didn't open DEUCE CLUB in the editor")
        keepScreenshot(named: "97-notice-unlock-opens-store")
    }

    /// WARM-UP's headphones came in: the notice names the store, never the piece, and a tap opens
    /// the store, where the piece's box opens and it is put on, while the rest stay boxes.
    func testAPieceThatCameInIsToldAndItsBoxOpens() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon",
            "-uitest-bubble-hold",
            "-today.cardPage", "0", "-uitest-unlocked-piece",
        ]
        app.launch()

        let banner = app.descendants(matching: .any).matching(identifier: "notice.banner").firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: Self.wait), "the notice never dropped in")
        XCTAssertTrue(banner.label.contains("WARM-UP 到新货了"), "the notice says \(banner.label)")
        XCTAssertTrue(banner.label.contains("随便练满 2 次"), "the notice says \(banner.label)")
        XCTAssertFalse(banner.label.contains("耳机"), "the notice gave the piece away: \(banner.label)")
        Thread.sleep(forTimeInterval: 0.6)
        keepScreenshot(named: "98-notice-piece-came-in")

        banner.tap()
        // The rack holds every piece of the store and its boxes hang last, so a box is far below
        // the fold, where the lazy grid hasn't drawn it yet.
        let mystery = app.descendants(matching: .any).matching(identifier: "editor.mystery.top").firstMatch
        XCTAssertTrue(scroll(to: mystery, in: app), "the store has no locked boxes")
        XCTAssertTrue(mystery.label.contains("再练"), "the box says \(mystery.label)")
        let piece = app.buttons["editor.tile.hat.warmup-headphones"]
        XCTAssertTrue(scroll(to: piece, in: app), "the headphones aren't on the rack")
        // The box opens, then the piece is put on.
        let worn = NSPredicate(format: "isSelected == true")
        expectation(for: worn, evaluatedWith: piece)
        waitForExpectations(timeout: Self.wait)
        keepScreenshot(named: "99-piece-unboxed")
    }

    /// Swipes the rack up (then back down) until the lazy grid has drawn `element`.
    private func scroll(to element: XCUIElement, in app: XCUIApplication) -> Bool {
        if element.waitForExistence(timeout: 2) { return true }
        for direction in [true, false] {
            for _ in 0..<24 where !element.exists {
                if direction { app.swipeUp(velocity: .fast) } else { app.swipeDown(velocity: .fast) }
            }
            if element.exists { return true }
        }
        return element.waitForExistence(timeout: Self.wait)
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
