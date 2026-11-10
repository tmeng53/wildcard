import XCTest

/// 商店街 from 我 on the in-memory member: its header button, the street and its map, a closed
/// store, WARM-UP's rack and its sports tip, and back. Keeps screenshots for review.
@MainActor
final class ShoppingStreetUITests: XCTestCase {
    /// 商店街 from its header button on 我, between 换装 and 设置: the map walks to a closed store, whose
    /// shutter and button say how it unlocks and whose tap keeps it shut; WARM-UP lets the member in, its ⓘ names the sports, and back walks out to
    /// the street and then to 我.
    /// 进店 sits at the bottom, just clear of the tab bar, under the map.
    private func assertEnterIsPinned(_ app: XCUIApplication) {
        let enter = app.buttons["street.enter"].frame
        let tabs = tabButton("tab.me", in: app).frame
        XCTAssertLessThanOrEqual(enter.maxY, tabs.minY, "the tab bar covers 进店: \(enter), \(tabs)")
        let map = app.buttons["street.map.warmup"].frame
        XCTAssertGreaterThan(enter.minY, map.maxY, "进店 isn't under the map")
        // The storefronts take the page's spare height, so no wide gap is left above the counter.
        let sports = app.descendants(matching: .any)["street.sports"].frame
        XCTAssertLessThan(sports.minY - map.maxY, 48, "a gap is left over the counter: \(map), \(sports)")
    }

    func testShoppingStreet() {
        let app = launch(language: "zh-Hans")
        let street = app.buttons["me.street"]
        XCTAssertTrue(street.waitForExistence(timeout: 30), "我 has no 商店街 button")
        XCTAssertLessThan(app.buttons["me.editCharacter"].frame.midX, street.frame.midX, "换装 isn't left of 商店街")
        XCTAssertLessThan(street.frame.midX, app.buttons["me.settings"].frame.midX, "商店街 isn't left of 设置")
        street.tap()
        let page = app.descendants(matching: .any).matching(identifier: "street.page").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 30), "商店街 never opened")
        let warmup = app.buttons["street.store.warmup"]
        XCTAssertTrue(warmup.waitForExistence(timeout: 30), "no WARM-UP on the street")
        settle()
        keepScreenshot(named: "22-street")
        assertEnterIsPinned(app)
        walkToClosedStore(app)
        let info = app.buttons["street.rack.info"]
        XCTAssertFalse(info.exists, "a closed store let the member in")
        let enter = app.buttons["street.enter"]
        // Back along the street to WARM-UP, and in through its button.
        app.buttons["street.map.warmup"].tap()
        settle()
        XCTAssertTrue(warmup.isHittable, "the map didn't walk back to WARM-UP")
        XCTAssertTrue(enter.isEnabled, "an open store's button is off")
        enter.tap()
        XCTAssertTrue(info.waitForExistence(timeout: 30), "WARM-UP didn't open")
        XCTAssertTrue(app.buttons["editor.tile.top.warmup-hoodie"].exists, "no 连帽卫衣 on WARM-UP's rack")
        info.tap()
        let tip = app.descendants(matching: .any).matching(identifier: "street.tip").firstMatch
        XCTAssertTrue(tip.waitForExistence(timeout: 30), "ⓘ didn't say which sports count")
        settle()
        keepScreenshot(named: "22-street-store")
        // The first tap may only put the tip away.
        let back = backButton(in: app)
        for _ in 0..<3 where !warmup.exists {
            back.tap()
            _ = warmup.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(warmup.exists, "back didn't walk out to the street")
        // Swiping back out of a store leaves the street where it was, not shifted half off screen
        // with its 返回 out of reach (2026-11-05).
        let backX = back.frame.minX
        warmup.tap()
        XCTAssertTrue(info.waitForExistence(timeout: 30), "WARM-UP didn't open again")
        // A swipe while the push is still sliding in lands on the rack, not the back gesture.
        settle()
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        XCTAssertTrue(warmup.waitForExistence(timeout: 30), "a swipe right didn't leave the store")
        settle()
        XCTAssertEqual(back.frame.minX, backX, accuracy: 2, "the street stayed shifted after a swipe back")
        XCTAssertTrue(back.isHittable, "返回 out of reach after a swipe back")
        back.tap()
        XCTAssertTrue(street.waitForExistence(timeout: 30), "back didn't return to 我")
    }

    /// A store that opens while the app is in the background (the winter switch turned on) is on
    /// the open street on the way back, without a relaunch (2026-11-06: TURKEY TROT stayed hidden
    /// until the app was killed).
    func testAStoreThatOpenedWhileAwayIsOnTheStreetOnReturn() {
        let app = launch(language: "zh-Hans", also: ["-uitest-winter-on-return"])
        let street = app.buttons["me.street"]
        XCTAssertTrue(street.waitForExistence(timeout: 30), "我 has no 商店街 button")
        street.tap()
        XCTAssertTrue(app.buttons["street.store.warmup"].waitForExistence(timeout: 30), "商店街 never opened")
        let powder = app.buttons["street.map.powder"]
        XCTAssertFalse(powder.exists, "POWDER DAY is on the street before winter")

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 30), "the app never went to the background")
        app.activate()
        XCTAssertTrue(powder.waitForExistence(timeout: 30), "POWDER DAY didn't open on the way back")
        powder.tap()
        settle()
        XCTAssertTrue(app.buttons["street.store.powder"].isHittable, "the map didn't walk to POWDER DAY")
        XCTAssertTrue(app.buttons["street.enter"].isEnabled, "POWDER DAY opened shut")
        keepScreenshot(named: "22-street-on-return")
    }

    /// The street's map walks to a closed store: its shutter and its button say how far it is from opening,
    /// and a tap on it keeps it shut.
    private func walkToClosedStore(_ app: XCUIApplication) {
        app.buttons["street.map.lap"].tap()
        let lap = app.buttons["street.store.lap"]
        XCTAssertTrue(lap.waitForExistence(timeout: 30), "the map didn't walk to LAP NINE")
        settle()
        XCTAssertTrue(lap.isHittable, "LAP NINE isn't in the middle of the street")
        XCTAssertTrue(lap.label.contains("还有 3 天开门"), lap.label)
        XCTAssertFalse(app.buttons["street.enter"].isEnabled, "a closed store's button lets the member in")
        keepScreenshot(named: "22-street-closed")
        lap.tap()
    }

    private func launch(language: String, also: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments +=
            [
                "-tab", "me", "-AppleLanguages", "(\(language))", "-AppleLocale", language, "-uitest-no-push",
            ] + also
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        return app
    }

    /// Thumbnails build and springs settle before a screenshot.
    private func settle() {
        Thread.sleep(forTimeInterval: 1.5)
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
