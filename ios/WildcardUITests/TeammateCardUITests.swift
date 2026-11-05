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

    func testFromSquadPage() {
        let app = launch(["-tab", "squad"])
        let row = app.buttons.matching(identifier: "squad.member.card").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.wait), "no teammate row opens a card")
        row.tap()
        let opened = app.buttons["me.card"].waitForExistence(timeout: Self.wait)
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot(named: "59-teammate-card-from-squad")
        XCTAssertTrue(opened, "the teammate's card didn't open:\n\(app.debugDescription)")
        let card = app.buttons["me.card"]
        XCTAssertTrue(app.windows.firstMatch.frame.contains(card.frame), "the card runs off the screen: \(card.frame)")
        // It pops up over the dimmed page, and a tap off it, above it, closes it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
        XCTAssertTrue(
            card.waitForNonExistence(timeout: 5), "a tap off the card didn't close it:\n\(app.debugDescription)")
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
