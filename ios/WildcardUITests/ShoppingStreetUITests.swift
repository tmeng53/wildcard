import XCTest

/// 商店街 from 我 on the in-memory member: its header button, a closed store, WARM-UP's rack and its
/// sports tip, and back. Keeps screenshots for review.
@MainActor
final class ShoppingStreetUITests: XCTestCase {
    /// 商店街 from its header button on 我, between 换装 and 设置: a closed store's card says how it unlocks and a
    /// tap keeps it shut; WARM-UP lets the member in, its ⓘ names the sports, and back walks out to
    /// the street and then to 我.
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
        let lap = app.buttons["street.store.lap"]
        for _ in 0..<6 where !lap.isHittable { app.swipeUp() }
        XCTAssertTrue(lap.label.contains("跑步 3 次解锁"), lap.label)
        lap.tap()
        let info = app.buttons["street.rack.info"]
        XCTAssertFalse(info.exists, "a closed store let the member in")
        for _ in 0..<6 where !warmup.isHittable { app.swipeDown() }
        warmup.tap()
        XCTAssertTrue(info.waitForExistence(timeout: 30), "WARM-UP didn't open")
        XCTAssertTrue(app.buttons["editor.tile.top.warmup-hoodie"].exists, "no 连帽卫衣 on WARM-UP's rack")
        info.tap()
        let tip = app.descendants(matching: .any).matching(identifier: "street.tip").firstMatch
        XCTAssertTrue(tip.waitForExistence(timeout: 30), "ⓘ didn't say which sports count")
        settle()
        keepScreenshot(named: "22-street-store")
        // The first tap may only put the tip away.
        let back = app.buttons["street.back"].firstMatch
        for _ in 0..<3 where !warmup.exists {
            back.tap()
            _ = warmup.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(warmup.exists, "back didn't walk out to the street")
        back.tap()
        XCTAssertTrue(street.waitForExistence(timeout: 30), "back didn't return to 我")
    }

    private func launch(language: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-tab", "me", "-AppleLanguages", "(\(language))", "-AppleLocale", language, "-uitest-no-push",
        ]
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
