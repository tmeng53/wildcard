import XCTest

/// The badge board on the back of 我's player card, on the in-memory member: the seven approved
/// titles three to a row with the 周日揭晓 slot, a badge's own card, and 装备 moving the tick and
/// the front's title. Screenshots are kept for review.
@MainActor
final class BadgeBoardUITests: XCTestCase {
    func testBoardAndEquip() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-tab", "me", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push",
        ]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        let card = app.buttons["me.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 30), "我 never showed")
        card.tap()
        let back = app.descendants(matching: .any).matching(identifier: "me.cardBack").firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "the card didn't turn over")
        let badges = app.buttons.matching(identifier: "me.badge")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "me.nextBadge").firstMatch.exists,
            "the board has no 周日揭晓 slot")
        XCTAssertEqual(badges.element(boundBy: 0).value as? String, "已装备", "the worn title has no tick")
        for index in 0..<badges.count where badges.element(boundBy: index).isHittable {
            let frame = badges.element(boundBy: index).frame
            XCTAssertTrue(back.frame.contains(frame), "badge \(index) runs off the card: \(frame)")
        }

        // A badge opens its card; 装备 wears it, and the board's tick moves to it.
        badges.element(boundBy: 1).tap()
        let detail = app.descendants(matching: .any).matching(identifier: "me.badgeCard").firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 5), "the badge didn't open")
        XCTAssertTrue(app.staticTexts["冷面杀手"].exists, "the badge card has no title")
        XCTAssertTrue(app.staticTexts["×2"].exists, "the badge card doesn't say it was won twice")
        XCTAssertTrue(app.staticTexts["10.19 – 10.25"].exists, "the badge card has no week chip")
        let equip = app.buttons["me.badgeCard.equip"]
        XCTAssertEqual(equip.label, "装备")
        XCTAssertTrue(app.windows.firstMatch.frame.contains(equip.frame), "装备 runs off the screen: \(equip.frame)")
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot(named: "42-me-badge-card")
        equip.tap()
        XCTAssertTrue(detail.waitForNonExistence(timeout: 5), "the badge card stayed open after 装备")
        waitFor(badges.element(boundBy: 1), "value == '已装备'", "the tick didn't move to 冷面杀手")

        // Turned back, the front wears it.
        back.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the card didn't turn back")
        waitFor(card, "label CONTAINS '冷面杀手'", "the front doesn't wear the equipped title")
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot(named: "43-me-card-equipped")
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
