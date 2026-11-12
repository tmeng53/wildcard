import XCTest

/// 开灯 on the home at 23:30, on the sample squad: the cord hangs under the folded card, clear of it and
/// of 打卡; tapping Coco opens her card, whose today says she's asleep; a tap on the cord switches the lights on, the
/// sleepers wake and Coco's status is her rest day; another tap switches them off. Screenshots of
/// each are kept for review.
@MainActor
final class LightsUITests: XCTestCase {
    /// Slow CI simulators can take many seconds to show a screen; a real failure still fails.
    private static let wait: TimeInterval = 30

    func testLightsAtNight() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-night",
            "-today.cardPage", "0", "-uitest-card-folded",
        ]
        app.launch()
        // The capsule's glass, not `today.card`, whose frame also takes in the 今日赛况 tag hanging
        // under the capsule's left end, beside the cord.
        let card = app.descendants(matching: .any).matching(identifier: "squadcard.capsule").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: Self.wait), "今天 never appeared folded")
        let cord = app.buttons["today.lights"]
        XCTAssertTrue(cord.waitForExistence(timeout: Self.wait), "no light cord at 23:30")
        XCTAssertEqual(cord.label, "开灯")
        expectClear(cord, of: card, in: app)
        settle()
        keepScreenshot(named: "71-today-night")

        // Asleep, Coco's today says so.
        mate("Coco", in: app).tap()
        let today = app.descendants(matching: .any).matching(identifier: "today.mateToday").firstMatch
        XCTAssertTrue(labeled("睡着了", in: today).waitForExistence(timeout: Self.wait), "Coco isn't asleep")
        Thread.sleep(forTimeInterval: 0.6)
        keepScreenshot(named: "71b-today-night-asleep")
        closePopup(today, in: app)

        // The tap follows the card's closing, which a busy simulator can still be ending.
        tap(cord, until: cord, "label == '关灯'", "the cord didn't switch the lights on")
        // Mid-wake: the first sleepers glaring up at the lamps, the first one's line.
        Thread.sleep(forTimeInterval: 1.6)
        keepScreenshot(named: "72-today-lights-waking")
        Thread.sleep(forTimeInterval: 3)
        keepScreenshot(named: "73-today-lights-on")
        expectClear(cord, of: card, in: app)

        // Awake, Coco is on her rest day.
        mate("Coco", in: app).tap()
        XCTAssertTrue(
            labeled("休息日", in: today).waitForExistence(timeout: Self.wait), "Coco didn't wake for the lights")
        XCTAssertFalse(labeled("睡着了", in: today).exists, "Coco still sleeps with the lights on")
        closePopup(today, in: app)

        tap(cord, until: cord, "label == '开灯'", "the cord didn't switch the lights off")
        Thread.sleep(forTimeInterval: 4.5)
        keepScreenshot(named: "74-today-lights-off")
    }

    /// The cord whole on screen, hanging under the card and above 打卡.
    private func expectClear(_ cord: XCUIElement, of card: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(cord.frame), "the cord runs off the screen: \(cord.frame)")
        XCTAssertGreaterThanOrEqual(cord.frame.minY, card.frame.maxY - 1, "the cord covers the card: \(cord.frame)")
        let tag = app.descendants(matching: .any).matching(identifier: "today.recap.tag").firstMatch
        if tag.exists {
            XCTAssertFalse(tag.frame.intersects(cord.frame), "the cord covers 今日赛况: \(cord.frame)")
        }
        let checkIn = app.buttons["today.checkin"]
        XCTAssertTrue(checkIn.exists, "no 打卡 button")
        XCTAssertLessThan(cord.frame.maxY, checkIn.frame.minY, "the cord reaches 打卡: \(cord.frame)")
    }

    /// A tap off the card, above it, closes the card and its today.
    private func closePopup(_ today: XCUIElement, in app: XCUIApplication) {
        tapOffPopup(above: today, in: app)
        XCTAssertTrue(today.waitForNonExistence(timeout: Self.wait), "a tap off the card left it open")
    }

    private func mate(_ nickname: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(identifier: "today.mate").matching(NSPredicate(format: "label == %@", nickname))
            .firstMatch
    }

    /// Any element showing exactly `label`.
    private func labeled(_ label: String, in app: XCUIElement) -> XCUIElement {
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
