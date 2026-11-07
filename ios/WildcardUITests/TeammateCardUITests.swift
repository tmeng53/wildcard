import XCTest

/// A teammate's player card, the way a member finds it: a tap on 小米 on the home opens her card
/// with her today over it, wearing her title, which turns over to her badge board and opens a
/// badge with no 装备; and from 小队's member list, where it pops up over the dimmed page and a
/// tap off it closes it. Screenshots are kept for review.
@MainActor
final class TeammateCardUITests: XCTestCase {
    private static let wait: TimeInterval = 30

    func testFromTheHome() {
        let app = launch(["-uitest-noon", "-today.cardPage", "0"])
        let mate = app.buttons.matching(identifier: "today.mate").matching(NSPredicate(format: "label == %@", "小米"))
            .firstMatch
        XCTAssertTrue(mate.waitForExistence(timeout: Self.wait), "小米 isn't on the home")
        mate.tap()
        let window = app.windows.firstMatch.frame
        let today = app.descendants(matching: .any).matching(identifier: "today.mateToday").firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: Self.wait), "her today didn't open over her card")
        XCTAssertTrue(window.contains(today.frame), "her today runs off the screen: \(today.frame)")
        let card = app.buttons["me.card"]
        let opened = card.waitForExistence(timeout: Self.wait)
        // Kept before the check, so a failure still shows what the screen held.
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot(named: "56-teammate-card")
        XCTAssertTrue(opened, "her card didn't open:\n\(app.debugDescription)")
        XCTAssertTrue(card.label.contains("小米"), "the card isn't hers: \(card.label)")
        XCTAssertTrue(card.label.contains("早八战神"), "the card doesn't wear her title: \(card.label)")
        XCTAssertTrue(window.contains(card.frame), "the card runs off the screen: \(card.frame)")
        XCTAssertLessThanOrEqual(today.frame.maxY, card.frame.minY, "her today covers her card: \(today.frame)")

        card.tap()
        let badges = app.buttons.matching(identifier: "me.badge")
        XCTAssertTrue(badges.firstMatch.waitForExistence(timeout: 5), "her card didn't turn over")
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot(named: "57-teammate-card-back")
        badges.element(boundBy: 0).tap()
        let detail = app.descendants(matching: .any).matching(identifier: "me.badgeCard").firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 5), "her badge didn't open")
        XCTAssertFalse(app.buttons["me.badgeCard.equip"].exists, "a teammate's badge offers 装备")
        Thread.sleep(forTimeInterval: 0.6)
        keepScreenshot(named: "58-teammate-badge-card")
    }

    /// From 小队's member list the card pops up over the dimmed page, and a tap off it closes it
    /// wherever it lands: above the card, just under the status bar, or where the tab bar is, which
    /// never switches the tab under the dim.
    func testFromSquadPageAndTapsOffTheCardNeverReachWhatIsUnderIt() {
        let app = launch(["-tab", "squad"])
        let row = app.buttons.matching(identifier: "squad.member.card").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.wait), "no teammate row opens a card")
        let feedTab = app.buttons["tab.feed"]
        XCTAssertTrue(feedTab.waitForExistence(timeout: Self.wait), "no 动态 tab")
        let card = app.buttons["me.card"]
        let window = app.windows.firstMatch.frame

        row.tap()
        let opened = card.waitForExistence(timeout: Self.wait)
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot(named: "59-teammate-card-from-squad")
        XCTAssertTrue(opened, "the teammate's card didn't open:\n\(app.debugDescription)")
        XCTAssertTrue(window.contains(card.frame), "the card runs off the screen: \(card.frame)")
        // A tap off it, above it, closes it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        XCTAssertTrue(
            card.waitForNonExistence(timeout: 5), "a tap off the card didn't close it:\n\(app.debugDescription)")
        XCTAssertTrue(row.isHittable, "小队 isn't back under the card")

        // A tap just under the status bar, where the page's own header sits, closes the card. (The
        // status bar itself takes taps for the system, so a test can't tap there.)
        row.tap()
        XCTAssertTrue(card.waitForExistence(timeout: Self.wait), "the teammate's card didn't open again")
        Thread.sleep(forTimeInterval: 0.6)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5), "a tap under the status bar didn't close the card")

        // A tap where the tab bar is closes it too, and never switches the tab under the dim.
        row.tap()
        XCTAssertTrue(card.waitForExistence(timeout: Self.wait), "the teammate's card didn't open a third time")
        Thread.sleep(forTimeInterval: 0.6)
        let tab = feedTab.frame
        app.coordinate(withNormalizedOffset: CGVector(dx: tab.midX / window.width, dy: tab.midY / window.height))
            .tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5), "a tap on the tab bar didn't close the card")
        XCTAssertFalse(feedTab.isSelected, "a tap meant for the dim switched to 动态 under the card")
        XCTAssertTrue(row.isHittable, "小队 isn't back under the card")
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push"] + extra
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        return app
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
