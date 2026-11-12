import XCTest

/// A teammate's player card, the way a member finds it: a tap on 小米 on the home opens her card
/// with her today over it, wearing her title, which turns over to her 出赛表 this week, whose
/// badges open her badge board and a badge with no 装备, and whose 穿搭 lists what she wears; and from 小队's member list, where it pops up over the dimmed page and a
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

        // Turned over, it is her 出赛表 this week: a row a day, her 饮食小目标, and her badges
        // along the bottom, which open her badge board.
        card.tap()
        let schedule = app.descendants(matching: .any).matching(identifier: "me.cardSchedule").firstMatch
        XCTAssertTrue(schedule.waitForExistence(timeout: 5), "her card didn't turn over to her 出赛表")
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot(named: "57-teammate-card-back")
        let back = app.descendants(matching: .any).matching(identifier: "me.cardBack").firstMatch
        XCTAssertTrue(back.frame.contains(schedule.frame), "her week runs off her card: \(schedule.frame)")
        let fuel = app.descendants(matching: .any).matching(identifier: "me.cardFuel").firstMatch
        XCTAssertTrue(fuel.exists, "her 饮食小目标 isn't on her card")
        XCTAssertTrue(back.frame.contains(fuel.frame), "her 饮食小目标 runs off her card: \(fuel.frame)")
        let openBoard = app.buttons["me.cardBadges"]
        XCTAssertTrue(openBoard.exists, "no badges on her card's back")
        XCTAssertTrue(back.frame.contains(openBoard.frame), "her badges run off her card: \(openBoard.frame)")
        assertOutfit(on: back, besides: openBoard, schedule: schedule, in: app)
        // Her badges turn the same side to her badge board, on her card, with no 周日揭晓 slot.
        openBoard.tap()
        let badges = app.buttons.matching(identifier: "me.badge")
        XCTAssertTrue(badges.firstMatch.waitForExistence(timeout: 5), "her badge board didn't open")
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot(named: "57b-teammate-badge-board")
        assertBoardInPlace(on: back, schedule: schedule, opener: openBoard, in: app)
        badges.element(boundBy: 0).tap()
        let detail = app.descendants(matching: .any).matching(identifier: "me.badgeCard").firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 5), "her badge didn't open")
        XCTAssertFalse(app.buttons["me.badgeCard.equip"].exists, "a teammate's badge offers 装备")
        Thread.sleep(forTimeInterval: 0.6)
        keepScreenshot(named: "58-teammate-badge-card")
    }

    /// Beside her badges, 穿搭 turns her card's back to what she wears, a row a piece, all on her
    /// card, and 「‹ 穿搭」 brings her 出赛表 back.
    private func assertOutfit(
        on back: XCUIElement, besides openBoard: XCUIElement, schedule: XCUIElement, in app: XCUIApplication
    ) {
        let openOutfit = app.buttons["me.cardOutfitRow"]
        XCTAssertTrue(openOutfit.exists, "no 穿搭 on her card's back")
        XCTAssertTrue(back.frame.contains(openOutfit.frame), "her 穿搭 runs off her card: \(openOutfit.frame)")
        XCTAssertLessThanOrEqual(openBoard.frame.maxX, openOutfit.frame.minX, "her badges cover her 穿搭")
        openOutfit.tap()
        let pieces = app.descendants(matching: .any).matching(identifier: "card.outfitPiece")
        XCTAssertTrue(pieces.firstMatch.waitForExistence(timeout: 5), "what she wears didn't open")
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot(named: "57a-teammate-outfit")
        XCTAssertGreaterThanOrEqual(pieces.count, 3, "her outfit lists fewer than a top, bottom and shoes")
        for index in 0..<pieces.count where pieces.element(boundBy: index).isHittable {
            let piece = pieces.element(boundBy: index).frame
            XCTAssertTrue(back.frame.contains(piece), "a piece runs off her card: \(piece)")
        }
        app.buttons["me.cardOutfitBack"].tap()
        XCTAssertTrue(schedule.waitForExistence(timeout: 5), "「‹ 穿搭」 didn't bring her 出赛表 back")
    }

    /// A tap on a teammate's ring in the squad card's 今天 row opens their card too, with their today
    /// over it, as a tap on them on the scene does (Tracy, 2026-11-10).
    func testFromTheSquadCardsRing() {
        let app = launch(["-uitest-noon", "-today.cardPage", "0", "-today.cardCollapsed", "0"])
        let ring = app.buttons.matching(identifier: "today.mateRing").firstMatch
        XCTAssertTrue(ring.waitForExistence(timeout: Self.wait), "no teammate's ring on the squad card")
        XCTAssertTrue(ring.isHittable, "the teammate's ring is covered")
        ring.tap()
        let today = app.descendants(matching: .any).matching(identifier: "today.mateToday").firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: Self.wait), "their today didn't open from their ring")
        let card = app.buttons["me.card"]
        XCTAssertTrue(card.waitForExistence(timeout: Self.wait), "their card didn't open from their ring")
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot(named: "56c-teammate-card-from-ring")
        XCTAssertTrue(app.windows.firstMatch.frame.contains(card.frame), "the card runs off the screen: \(card.frame)")
    }

    /// A teammate's badge board sits on her card's back, with no 周日揭晓 slot, and 「‹ 出赛表」
    /// brings her 出赛表 back; it ends with the board open again.
    private func assertBoardInPlace(
        on back: XCUIElement, schedule: XCUIElement, opener openBoard: XCUIElement, in app: XCUIApplication
    ) {
        let badges = app.buttons.matching(identifier: "me.badge")
        XCTAssertTrue(back.frame.contains(badges.firstMatch.frame), "her board isn't on her card")
        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: "me.nextBadge").firstMatch.exists,
            "her board shows the 周日揭晓 slot")
        let toSchedule = app.buttons["me.cardBackToSchedule"]
        XCTAssertTrue(toSchedule.exists, "her board has no way back to her 出赛表")
        // The same 「‹ side」 back as 穿搭's, naming the side it is on.
        XCTAssertTrue(toSchedule.label.contains("徽章"), "her board's back isn't 「‹ 徽章」: \(toSchedule.label)")
        toSchedule.tap()
        XCTAssertTrue(schedule.waitForExistence(timeout: 5), "「‹ 徽章」 didn't bring her 出赛表 back")
        openBoard.tap()
        XCTAssertTrue(badges.firstMatch.waitForExistence(timeout: 5), "her badge board didn't open again")
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
