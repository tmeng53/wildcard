import XCTest

/// 开灯 on the home at 23:30, on the sample squad: the cord hangs under the card, clear of it and
/// of 打卡; tapping Coco says she's asleep; a tap on the cord switches the lights on, the
/// sleepers wake and Coco's status is her rest day; another tap switches them off. Screenshots of
/// each are kept for review.
@MainActor
final class LightsUITests: XCTestCase {
    /// Slow CI simulators can take many seconds to show a screen; a real failure still fails.
    private static let wait: TimeInterval = 30
    /// The squad card's page dots, under the white card, answer taps this tall.
    private static let pageDots: CGFloat = 44

    func testLightsAtNight() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-night",
            "-today.cardPage", "0",
        ]
        app.launch()
        let card = app.descendants(matching: .any).matching(identifier: "today.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: Self.wait), "今天 never appeared")
        let cord = app.buttons["today.lights"]
        XCTAssertTrue(cord.waitForExistence(timeout: Self.wait), "no light cord at 23:30")
        XCTAssertEqual(cord.label, "开灯")
        expectClear(cord, of: card, in: app)
        settle()
        keepScreenshot(named: "71-today-night")

        // Asleep, Coco's bubble says so.
        mate("Coco", in: app).tap()
        XCTAssertTrue(labeled("Coco · 睡着了", in: app).waitForExistence(timeout: Self.wait), "Coco isn't asleep")
        let bubble = app.descendants(matching: .any).matching(identifier: "today.patBubble").firstMatch
        XCTAssertFalse(bubble.frame.intersects(cord.frame), "the bubble covers the cord: \(bubble.frame)")

        cord.tap()
        // Mid-wake: the first sleepers glaring up at the lamps, the first one's line.
        Thread.sleep(forTimeInterval: 1.6)
        keepScreenshot(named: "72-today-lights-waking")
        XCTAssertEqual(cord.label, "关灯")
        Thread.sleep(forTimeInterval: 3)
        keepScreenshot(named: "73-today-lights-on")
        expectClear(cord, of: card, in: app)

        // Awake, Coco is on her rest day.
        mate("Coco", in: app).tap()
        XCTAssertTrue(
            labeled("Coco · 今天是休息日", in: app).waitForExistence(timeout: Self.wait), "Coco didn't wake for the lights")
        XCTAssertFalse(labeled("Coco · 睡着了", in: app).exists, "Coco still sleeps with the lights on")

        cord.tap()
        XCTAssertEqual(cord.label, "开灯")
        Thread.sleep(forTimeInterval: 4.5)
        keepScreenshot(named: "74-today-lights-off")
    }

    /// The cord whole on screen, hanging under the white card (the page dots' row, 44 tall, is the
    /// card element's last part) and above 打卡.
    private func expectClear(_ cord: XCUIElement, of card: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(cord.frame), "the cord runs off the screen: \(cord.frame)")
        let cardBottom = card.frame.maxY - Self.pageDots
        XCTAssertGreaterThanOrEqual(cord.frame.minY, cardBottom - 1, "the cord covers the card: \(cord.frame)")
        XCTAssertLessThan(cord.frame.minY, cardBottom + 40, "the cord hangs away from the card: \(cord.frame)")
        let checkIn = app.buttons["today.checkin"]
        XCTAssertTrue(checkIn.exists, "no 打卡 button")
        XCTAssertLessThan(cord.frame.maxY, checkIn.frame.minY, "the cord reaches 打卡: \(cord.frame)")
    }

    private func mate(_ nickname: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(identifier: "today.mate").matching(NSPredicate(format: "label == %@", nickname))
            .firstMatch
    }

    /// Any element showing exactly `label`.
    private func labeled(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Lets springs and the characters' entrances settle before a screenshot.
    private func settle() {
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
