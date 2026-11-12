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

    /// A badge the team gave: NEW until opened, its card from 外卡团队, and 装备 wears it on the
    /// front in place of a title.
    func testTeamBadgeIsNewAndWearable() {
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
        let ticket = app.buttons["me.teamBadge"]
        XCTAssertTrue(ticket.waitForExistence(timeout: 5), "the board has no team badge")
        // NEW is drawn inside the badge, which reads as one element: its value says it.
        XCTAssertEqual(ticket.value as? String, "NEW", "the team badge given just now isn't NEW")
        XCTAssertTrue(back.frame.contains(ticket.frame), "the team badge runs off the card: \(ticket.frame)")
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot(named: "44-me-team-badge-new")

        ticket.tap()
        let detail = app.descendants(matching: .any).matching(identifier: "me.badgeCard").firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 5), "the team badge didn't open")
        XCTAssertTrue(app.staticTexts["点子王"].exists, "the team badge's card has no name")
        XCTAssertTrue(app.staticTexts["外卡团队"].exists, "the team badge's card doesn't say who gave it")
        XCTAssertTrue(app.staticTexts["首席点子官"].exists, "the team badge's card has no line")
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot(named: "45-me-team-badge-card")
        app.buttons["me.badgeCard.equip"].tap()
        XCTAssertTrue(detail.waitForNonExistence(timeout: 5), "the badge card stayed open after 装备")
        waitFor(ticket, "value == '已装备'", "the tick didn't move to 点子王")

        back.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the card didn't turn back")
        waitFor(card, "label CONTAINS '点子王'", "the front doesn't wear the team badge")
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot(named: "46-me-card-team-badge")
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
