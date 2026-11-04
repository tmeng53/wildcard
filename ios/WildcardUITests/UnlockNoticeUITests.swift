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

    /// WARM-UP's headphones came in: the notice names the store, never the piece, and a tap puts
    /// up its box; 一键全开 opens it onto the shopping street, where WARM-UP and the piece wear NEW
    /// until the piece is tapped. Nothing is put on by itself.
    func testAPieceThatCameInIsToldAndItsBoxOpens() {
        continueAfterFailure = false
        let app = launchWithAPieceCameIn()
        let banner = app.descendants(matching: .any).matching(identifier: "notice.banner").firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: Self.wait), "the notice never dropped in")
        XCTAssertTrue(banner.label.contains("WARM-UP 到新货了"), "the notice says \(banner.label)")
        XCTAssertTrue(banner.label.contains("随便练满 2 次"), "the notice says \(banner.label)")
        XCTAssertFalse(banner.label.contains("耳机"), "the notice gave the piece away: \(banner.label)")
        Thread.sleep(forTimeInterval: 0.6)
        keepScreenshot(named: "98-notice-piece-came-in")

        banner.tap()
        let popup = waitForArrival(in: app)
        Thread.sleep(forTimeInterval: 0.4)
        keepScreenshot(named: "99-piece-arrival-popup")
        app.buttons["editor.arrival.open"].tap()
        XCTAssertTrue(popup.waitForNonExistence(timeout: Self.wait), "the pop-up stayed up")
        // On the shopping street, the store with news marked.
        let news = app.descendants(matching: .any).matching(identifier: "editor.store.warmup.new").firstMatch
        XCTAssertTrue(news.waitForExistence(timeout: Self.wait), "WARM-UP has no NEW on the street")
        keepScreenshot(named: "100-piece-boxes-opened")
        app.descendants(matching: .any).matching(identifier: "editor.store.warmup").firstMatch.tap()
        let mystery = app.descendants(matching: .any).matching(identifier: "editor.mystery.top").firstMatch
        XCTAssertTrue(mystery.waitForExistence(timeout: Self.wait), "the store has no locked boxes")
        XCTAssertTrue(mystery.label.contains("再练"), "the box says \(mystery.label)")
        let piece = app.buttons["editor.tile.hat.warmup-headphones"]
        XCTAssertTrue(piece.waitForExistence(timeout: Self.wait), "the headphones aren't on the rack")
        XCTAssertFalse(piece.isSelected, "the headphones were put on by themselves")
        let tag = app.descendants(matching: .any).matching(identifier: "editor.tile.hat.warmup-headphones.new")
            .firstMatch
        XCTAssertTrue(tag.exists, "the headphones wear no NEW")
        keepScreenshot(named: "101-piece-new-on-rack")
        piece.tap()
        XCTAssertTrue(tag.waitForNonExistence(timeout: Self.wait), "NEW stayed after the tap")
        XCTAssertTrue(piece.isSelected, "the tap didn't try the headphones on")
    }

    /// 先不了 leaves the box on its rack, 「可以开了」, and a tap on it puts the pop-up up again.
    func testAPieceLeftInItsBoxWaitsOnItsRack() {
        continueAfterFailure = false
        let app = launchWithAPieceCameIn()
        let banner = app.descendants(matching: .any).matching(identifier: "notice.banner").firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: Self.wait), "the notice never dropped in")
        banner.tap()
        let popup = waitForArrival(in: app)
        app.buttons["editor.arrival.leave"].tap()
        XCTAssertTrue(popup.waitForNonExistence(timeout: Self.wait), "the pop-up stayed up")
        let store = app.descendants(matching: .any).matching(identifier: "editor.store.warmup").firstMatch
        XCTAssertTrue(store.waitForExistence(timeout: Self.wait), "the shopping street isn't showing")
        store.tap()
        let ready = app.descendants(matching: .any).matching(identifier: "editor.ready.hat").firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: Self.wait), "the box isn't waiting on the rack")
        XCTAssertFalse(app.buttons["editor.tile.hat.warmup-headphones"].exists, "the box showed its piece")
        ready.tap()
        _ = waitForArrival(in: app)
    }

    private func launchWithAPieceCameIn() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon",
            "-uitest-bubble-hold",
            "-today.cardPage", "0", "-uitest-unlocked-piece",
        ]
        app.launch()
        return app
    }

    /// The pop-up the editor opens with: the box and its store, never the piece.
    private func waitForArrival(in app: XCUIApplication) -> XCUIElement {
        let popup = app.descendants(matching: .any).matching(identifier: "editor.arrival").firstMatch
        XCTAssertTrue(popup.waitForExistence(timeout: Self.wait), "the editor opened without the pop-up")
        let words = popup.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        XCTAssertTrue(words.contains("WARM-UP 到新货了"), "the pop-up says \(words)")
        XCTAssertFalse(words.contains("耳机"), "the pop-up gave the piece away: \(words)")
        XCTAssertTrue(app.buttons["editor.arrival.open"].exists, "the pop-up has no 一键全开")
        XCTAssertFalse(app.buttons["editor.tile.hat.warmup-headphones"].exists, "the piece shows under the pop-up")
        return popup
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
