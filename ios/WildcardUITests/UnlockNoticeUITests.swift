import XCTest

/// The sample member's training has just opened DEUCE CLUB (or brought WARM-UP a new piece): 今天
/// drops the notice in, whole on screen and on one line each for its title and detail, and a tap
/// on it opens the store on 我's 商店街. Screenshots are kept for review.
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
        let rack = app.buttons["editor.tile.top.deuce-polo"]
        XCTAssertTrue(rack.waitForExistence(timeout: Self.wait), "the tap didn't open DEUCE CLUB on 商店街")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "street.page").firstMatch.exists,
            "DEUCE CLUB opened somewhere else than 商店街")
        keepScreenshot(named: "97-notice-unlock-opens-store")
    }

    /// WARM-UP's headphones came in: the notice names the store, never the piece, and a tap opens
    /// WARM-UP's rack on 商店街, where the piece wears NEW, with no box to open first (Tracy,
    /// 2026-11-08). Nothing is put on by itself: a tap offers 领取, which puts it in the wardrobe,
    /// and 「已放进衣橱」's 穿上看看 opens the editor wearing it.
    func testAPieceThatCameInIsToldAndWaitsOnItsRack() {
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
        let mystery = app.descendants(matching: .any).matching(identifier: "editor.mystery.top").firstMatch
        XCTAssertTrue(mystery.waitForExistence(timeout: Self.wait), "WARM-UP's rack has no locked boxes")
        XCTAssertTrue(mystery.label.contains("再练"), "the box says \(mystery.label)")
        let piece = app.buttons["editor.tile.hat.warmup-headphones"]
        XCTAssertTrue(piece.waitForExistence(timeout: Self.wait), "the headphones aren't on the rack")
        let tag = app.descendants(matching: .any).matching(identifier: "editor.tile.hat.warmup-headphones.new")
            .firstMatch
        XCTAssertTrue(tag.exists, "the headphones wear no NEW")
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot(named: "100-piece-new-on-rack")

        piece.tap()
        let claim = app.buttons["street.claim"]
        XCTAssertTrue(claim.waitForExistence(timeout: Self.wait), "a tap on NEW didn't offer 领取")
        Thread.sleep(forTimeInterval: 0.8)
        keepScreenshot(named: "101-piece-claim-sheet")
        claim.tap()
        // Every notice banner is one element named notice.banner (#463); this one says 已放进衣橱.
        // `-uitest-bubble-hold` keeps it up a minute, since on a busy CI simulator the queries
        // before the tap outlast its few seconds. The rack after 领取 is checked in
        // testAClaimedPieceIsOwnedOnItsRack.
        let claimed = app.descendants(matching: .any).matching(identifier: "notice.banner")
            .matching(NSPredicate(format: "label CONTAINS %@", "已放进衣橱")).firstMatch
        XCTAssertTrue(claimed.waitForExistence(timeout: Self.wait), "「已放进衣橱」 never dropped in")
        keepScreenshot(named: "102-piece-claimed")
        claimed.tap()
        // The editor's own tile: the rack under the editor has a tile of the same name.
        let worn = app.descendants(matching: .any).matching(identifier: "editor.wardrobe").firstMatch
            .buttons["editor.tile.hat.warmup-headphones"]
        XCTAssertTrue(app.buttons["editor.done"].waitForExistence(timeout: Self.wait), "穿上看看 didn't open the editor")
        XCTAssertTrue(worn.waitForExistence(timeout: Self.wait), "the headphones aren't in the wardrobe")
        waitFor(worn, "isSelected == true", "穿上看看 didn't put the headphones on")
        Thread.sleep(forTimeInterval: 1.5)
        keepScreenshot(named: "103-piece-tried-on")
    }

    /// A piece that came in shows on its rack as itself, never a 「？」 box, with NEW; a tap on it
    /// offers 领取, after which the rack shows it owned.
    func testAClaimedPieceIsOwnedOnItsRack() {
        continueAfterFailure = false
        let app = launchWithAPieceCameIn()
        let banner = app.descendants(matching: .any).matching(identifier: "notice.banner").firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: Self.wait), "the notice never dropped in")
        banner.tap()
        let piece = app.buttons["editor.tile.hat.warmup-headphones"]
        XCTAssertTrue(piece.waitForExistence(timeout: Self.wait), "the piece isn't waiting on the rack")
        let tag = app.descendants(matching: .any).matching(identifier: "editor.tile.hat.warmup-headphones.new")
            .firstMatch
        XCTAssertTrue(tag.exists, "the piece waits without NEW")
        piece.tap()
        let take = app.buttons["street.claim"]
        XCTAssertTrue(take.waitForExistence(timeout: Self.wait), "a tap didn't offer 领取")
        // 领取 puts it in the wardrobe: the rack shows it owned, without NEW.
        take.tap()
        let owned = app.descendants(matching: .any).matching(identifier: "editor.tile.hat.warmup-headphones.owned")
            .firstMatch
        XCTAssertTrue(owned.waitForExistence(timeout: Self.wait), "the headphones aren't 已拥有 after 领取")
        XCTAssertFalse(tag.exists, "NEW stayed after 领取")
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
