import XCTest

/// The coach's page as the approved deck has it (Tracy, 2026-11-08): with a morning note waiting,
/// the phone in 毛头's hand shows a dot and the note never slides up over 今天 by itself; a tap on
/// 毛头 opens its page, a stack of what it has for me, oldest on top. Each card is swiped right
/// into 以前; a gift opens in place (拆开, then 立刻穿上) and a challenge is answered in place
/// (接受挑战). Under the stack a line says how many are left (Tracy, 2026-11-09). Once all are seen,
/// what 毛头 said last stays up and the clock opens 以前, where every card is a row and 挑战 keeps only the challenges. Screenshots are
/// kept for review.
@MainActor
final class CoachDeckUITests: XCTestCase {
    private static let wait: TimeInterval = 30

    func testEveryCardIsSeenInTurnAndGoesIntoEarlier() {
        continueAfterFailure = false
        let app = launch()
        // The squad card says the home is up; 打卡 is the system tab bar's ＋ since #929, which
        // doesn't always carry its identifier.
        let squadCard = app.descendants(matching: .any).matching(identifier: "today.card").firstMatch
        XCTAssertTrue(squadCard.waitForExistence(timeout: Self.wait), "the home didn't open")
        let coach = app.buttons["today.coach"]
        XCTAssertTrue(coach.waitForExistence(timeout: Self.wait), "毛头 isn't on the sideline")
        expectation(for: NSPredicate(format: "value == %@", "有新消息"), evaluatedWith: coach)
        waitForExpectations(timeout: Self.wait)
        XCTAssertTrue(coach.isHittable, "毛头 is covered")
        keepScreenshot(named: "105-coach-note-waiting")

        coach.tap()
        // 对小队说: 去动态看看.
        let board = card("board", in: app)
        XCTAssertTrue(board.waitForExistence(timeout: Self.wait), "the page didn't open on the line to the squad")
        // The top card leans right and back once as the page opens; let it settle first.
        Thread.sleep(forTimeInterval: 1.5)
        assertOnScreen(board, app.buttons["coachDeck.feed"], in: app)
        assertUnderTheBar(board, in: app)
        let cardFrame = board.frame
        // Under the stack: how many are left after this one, and 下一张.
        let hint = element("coachDeck.hint", in: app)
        XCTAssertTrue(hint.waitForExistence(timeout: Self.wait), "nothing says how many cards are left")
        XCTAssertEqual(hint.label, "还有 3 张")
        let next = app.buttons["coachDeck.next"]
        for under in [hint, next] {
            XCTAssertTrue(app.windows.firstMatch.frame.contains(under.frame), "it runs off the screen: \(under.frame)")
            XCTAssertGreaterThanOrEqual(under.frame.minY, board.frame.maxY, "it is on the card")
        }
        XCTAssertTrue(next.isHittable, "下一张 is covered")
        assertOnlyEdgesPeek(under: board, in: app)
        keepScreenshot(named: "106-coach-deck-board")
        putAway(board, in: app)

        turnTheNote(with: next, sameAs: cardFrame, in: app)

        openAndWear(sameAs: cardFrame, in: app)
        accept(sameAs: cardFrame, in: app)
        // The coach's lines to my check-ins stay under the posts in 动态, never here.

        // All seen: the newest card stays up, with no empty card and no 以前 button (Tracy,
        // 2026-11-26); the clock opens 以前, newest first.
        let latest = element("coachDeck.latest", in: app)
        XCTAssertTrue(latest.waitForExistence(timeout: Self.wait), "the newest card didn't stay up")
        XCTAssertFalse(element("coachDeck.allSeen", in: app).exists, "the page shows an empty card")
        XCTAssertFalse(app.buttons["coachDeck.earlier"].exists, "the page shows a 以前 button")
        XCTAssertTrue(app.windows.firstMatch.frame.contains(latest.frame), "the newest card runs off the screen")
        assertSame(latest, as: cardFrame)
        keepScreenshot(named: "113-coach-deck-all-seen")
        app.buttons["coachDeck.history"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "coachEarlier.row."))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: Self.wait), "以前 didn't open")
        XCTAssertEqual(rows.count, 4, "以前 doesn't list every card seen")
        XCTAssertEqual(rows.firstMatch.identifier, "coachEarlier.row.challenge", "以前 isn't newest first")
        keepScreenshot(named: "114-coach-earlier")

        // 挑战 keeps only the challenges (Tracy, 2026-11-09).
        app.buttons["挑战"].tap()
        let challenges = app.buttons.matching(identifier: "coachEarlier.row.challenge")
        XCTAssertTrue(challenges.firstMatch.waitForExistence(timeout: Self.wait), "挑战 lists no challenge")
        XCTAssertEqual(rows.count, challenges.count, "挑战 lists more than challenges")
        keepScreenshot(named: "114b-coach-earlier-challenges")
    }

    /// 不接挑战 with a word to 毛头 on why: the field and 不接挑战 stay above the keyboard while it
    /// is typed, and the card goes once it is sent.
    func testTheReasonForPassingStaysAboveTheKeyboard() {
        continueAfterFailure = false
        let app = launch()
        let coach = app.buttons["today.coach"]
        XCTAssertTrue(coach.waitForExistence(timeout: Self.wait), "毛头 isn't on the sideline")
        coach.tap()
        for kind in ["board", "note", "gift"] {
            let next = card(kind, in: app)
            XCTAssertTrue(next.waitForExistence(timeout: Self.wait), "the \(kind) isn't next")
            putAway(next, in: app)
        }
        let challenge = card("challenge", in: app)
        waitFor(element("coachDeck.hint", in: app), "label == '最后一张'", "the last card doesn't say it is the last")
        // Only a quiet 不接挑战 until it is tapped; then the field for why and the 不接挑战 that sends it.
        XCTAssertFalse(element("coachDeck.reason", in: app).exists, "the field for why shows before 不接挑战")
        app.buttons["coachDeck.pass"].tap()
        let reason = element("coachDeck.reason", in: app)
        XCTAssertTrue(reason.waitForExistence(timeout: Self.wait), "the challenge has no field for why")
        XCTAssertEqual(reason.placeholderValue, "原因（可选）")
        reason.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: Self.wait), "the keyboard isn't up")
        reason.typeText("我鸡蛋过敏")
        Thread.sleep(forTimeInterval: 1)
        let decline = app.buttons["coachDeck.decline"]
        XCTAssertLessThanOrEqual(reason.frame.maxY, keyboard.frame.minY, "the keyboard covers the field")
        XCTAssertLessThanOrEqual(decline.frame.maxY, keyboard.frame.minY, "the keyboard covers 不接挑战")
        XCTAssertTrue(decline.isHittable, "不接挑战 is covered")
        keepScreenshot(named: "116-coach-deck-challenge-reason")
        decline.tap()
        waitFor(challenge, "exists == false", "the challenge stayed after 不接挑战")
    }

    /// A gift swiped away in its box stays boxed in 以前, and opens from there.
    func testAGiftSwipedAwayBoxedOpensFromEarlier() {
        continueAfterFailure = false
        let app = launch(extra: ["-uitest-coach-seen"])
        let coach = app.buttons["today.coach"]
        XCTAssertTrue(coach.waitForExistence(timeout: Self.wait), "毛头 isn't on the sideline")
        coach.tap()
        let history = app.buttons["coachDeck.history"]
        XCTAssertTrue(history.waitForExistence(timeout: Self.wait), "the page has no 以前")
        history.tap()
        let gift = app.buttons["coachEarlier.row.gift"]
        XCTAssertTrue(gift.waitForExistence(timeout: Self.wait), "以前 has no gift")
        gift.tap()
        let unwrap = app.buttons["coachDeck.unwrap"]
        XCTAssertTrue(unwrap.waitForExistence(timeout: Self.wait), "the boxed gift doesn't open from 以前")
        assertOnScreen(card("gift", in: app), unwrap, in: app)
        unwrap.tap()
        app.buttons["coachDeck.later"].tap()
        XCTAssertTrue(
            app.buttons["coachDeck.wardrobe"].waitForExistence(timeout: Self.wait), "一会儿再说 didn't put it away")
        keepScreenshot(named: "115-coach-earlier-gift-later")
    }

    /// 今天对你说: no button of its own. The card is the same size as the one before it (Tracy,
    /// 2026-11-26), and 下一张 turns it.
    private func turnTheNote(with next: XCUIElement, sameAs cardFrame: CGRect, in app: XCUIApplication) {
        let note = card("note", in: app)
        XCTAssertTrue(note.waitForExistence(timeout: Self.wait), "the morning note isn't next")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertLessThan(
            note.frame.maxY, next.frame.minY, "下一张 isn't under the note: \(note.frame), \(next.frame)")
        assertSame(note, as: cardFrame)
        keepScreenshot(named: "107-coach-deck-note")
        next.tap()
        waitFor(note, "exists == false", "下一张 didn't put the note away")
    }

    /// A gift still in its box puts a round gift button under the card (Tracy, 2026-11-21), which
    /// opens the gift's card over the coach's page, ready to 拆开, both folded and open.
    func testTheHomesGiftButtonOpensTheBoxedGift() {
        continueAfterFailure = false
        for folded in [true, false] {
            let app = launch(extra: ["-uitest-coach-gift"], folded: folded)
            let button = app.buttons["today.gift"]
            XCTAssertTrue(button.waitForExistence(timeout: Self.wait), "no gift button")
            XCTAssertTrue(button.isHittable, "the gift button is covered")
            let card = app.descendants(matching: .any).matching(identifier: "today.card").firstMatch
            XCTAssertGreaterThanOrEqual(button.frame.minY, card.frame.maxY, "the gift button sits on the card")
            XCTAssertTrue(app.windows.firstMatch.frame.contains(button.frame), "the gift button is off screen")
            keepScreenshot(named: folded ? "116-home-gift-button-folded" : "117-home-gift-button")
            button.tap()
            let unwrap = app.buttons["coachDeck.unwrap"]
            XCTAssertTrue(unwrap.waitForExistence(timeout: Self.wait), "the gift button didn't open the boxed gift")
            assertOnScreen(self.card("gift", in: app), unwrap, in: app)
            keepScreenshot(named: folded ? "118-home-gift-opened-card" : "119-home-gift-opened-card-open")
            app.terminate()
        }
    }

    /// 送你的: 拆开, then 立刻穿上, then 去衣橱看看.
    private func openAndWear(sameAs cardFrame: CGRect, in app: XCUIApplication) {
        let gift = card("gift", in: app)
        XCTAssertTrue(gift.waitForExistence(timeout: Self.wait), "the gift isn't next")
        let unwrap = app.buttons["coachDeck.unwrap"]
        assertOnScreen(gift, unwrap, in: app)
        assertSame(gift, as: cardFrame)
        keepScreenshot(named: "108-coach-deck-gift")
        unwrap.tap()
        let wear = app.buttons["coachDeck.wear"]
        XCTAssertTrue(wear.waitForExistence(timeout: Self.wait), "拆开 didn't offer 立刻穿上")
        XCTAssertTrue(app.buttons["coachDeck.later"].isHittable, "一会儿再说 is covered")
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot(named: "109-coach-deck-gift-open")
        wear.tap()
        let wardrobe = app.buttons["coachDeck.wardrobe"]
        XCTAssertTrue(wardrobe.waitForExistence(timeout: Self.wait), "立刻穿上 didn't offer 去衣橱看看")
        Thread.sleep(forTimeInterval: 1)
        keepScreenshot(named: "110-coach-deck-gift-worn")
        putAway(gift, in: app)

    }

    /// 今日挑战: 接受挑战 answers it, stamps the button, and the card goes on its own.
    private func accept(sameAs cardFrame: CGRect, in app: XCUIApplication) {
        let challenge = card("challenge", in: app)
        XCTAssertTrue(challenge.waitForExistence(timeout: Self.wait), "the challenge isn't next")
        let accept = app.buttons["coachDeck.accept"]
        assertOnScreen(challenge, accept, in: app)
        assertSame(challenge, as: cardFrame)
        XCTAssertTrue(app.buttons["coachDeck.pass"].isHittable, "不接挑战 is covered")
        XCTAssertTrue(challenge.frame.contains(app.buttons["coachDeck.pass"].frame), "不接挑战 runs off its card")
        keepScreenshot(named: "111-coach-deck-challenge")
        accept.tap()
        waitFor(challenge, "exists == false", "the challenge stayed after it was accepted")

    }

    /// While 毛头 said something I haven't seen, the squad card's last row says its name and the
    /// start of its newest line (Tracy, 2026-11-13, option 1); a tap opens its page on today's cards.
    func testTheSquadCardsCoachRowOpensWhatTheCoachSaid() {
        continueAfterFailure = false
        let app = launch(folded: false)
        let row = app.buttons["squadcard.coachNews"]
        XCTAssertTrue(row.waitForExistence(timeout: Self.wait), "the squad card has no row for 毛头")
        XCTAssertEqual(row.label, "毛头")
        XCTAssertTrue(
            (row.value as? String)?.hasPrefix("昨天三个人上场") ?? false, "the row doesn't say 毛头's line: \(row.value ?? "")")
        let squadCard = app.descendants(matching: .any).matching(identifier: "today.card").firstMatch
        XCTAssertTrue(
            squadCard.frame.contains(row.frame), "the row runs off the squad card: \(row.frame) in \(squadCard.frame)")
        XCTAssertTrue(app.windows.firstMatch.frame.contains(row.frame), "the row runs off the screen: \(row.frame)")
        XCTAssertTrue(row.isHittable, "the row is covered")
        keepScreenshot(named: "104-coach-news-row")

        row.tap()
        XCTAssertTrue(
            card("board", in: app).waitForExistence(timeout: Self.wait), "the row didn't open 毛头's page")
    }

    private func launch(extra: [String] = [], folded: Bool = true, night: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments +=
            [
                "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push",
                night ? "-uitest-night" : "-uitest-noon",
                "-today.cardPage", "0", "-uitest-coach-note",
            ] + extra
        // Home opens on the folded capsule, as most of these tests were written for.
        app.launchArguments += folded ? ["-uitest-card-folded"] : ["-today.cardCollapsed", "NO"]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        return app
    }

    /// Swipes the top card right, into 以前.
    private func putAway(_ card: XCUIElement, in app: XCUIApplication) {
        swipeTopCoachCard(in: app)
        waitFor(card, "exists == false", "the swipe didn't put \(card.identifier) away")
    }

    private func card(_ kind: String, in app: XCUIApplication) -> XCUIElement {
        element("coachDeck.card.\(kind)", in: app)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The card is all on screen, and its button is free and on it.
    private func assertOnScreen(_ card: XCUIElement, _ button: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(button.waitForExistence(timeout: Self.wait), "\(card.identifier) has no \(button.identifier)")
        let screen = app.windows.firstMatch.frame
        XCTAssertTrue(screen.contains(card.frame), "\(card.identifier) runs off the screen: \(card.frame)")
        XCTAssertTrue(card.frame.contains(button.frame), "\(button.identifier) runs off its card")
        XCTAssertTrue(button.isHittable, "\(button.identifier) is covered")
    }

    private func waitFor(_ element: XCUIElement, _ format: String, _ message: String) {
        let met = expectation(for: NSPredicate(format: format), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [met], timeout: Self.wait), .completed, message)
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Where the coach page puts its cards.
extension CoachDeckUITests {
    /// The card starts under the navigation bar, and its sides line up with the bar's buttons: the
    /// page's margin from the screen's edges.
    func assertUnderTheBar(_ card: XCUIElement, in app: XCUIApplication) {
        let bar = app.navigationBars.firstMatch.frame
        let screen = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(
            card.frame.minY, bar.maxY, "\(card.identifier) runs up under the bar: \(card.frame)")
        XCTAssertEqual(card.frame.minX, screen.minX + 16, accuracy: 1, "\(card.identifier) isn't on the page margin")
        XCTAssertEqual(card.frame.maxX, screen.maxX - 16, accuracy: 1, "\(card.identifier) isn't on the page margin")
    }

    /// Every card on the page is the same size, in the same place (Tracy, 2026-11-26).
    func assertSame(_ card: XCUIElement, as cardFrame: CGRect) {
        XCTAssertEqual(card.frame.minY, cardFrame.minY, accuracy: 1, "\(card.identifier) moved: \(card.frame)")
        XCTAssertEqual(card.frame.height, cardFrame.height, accuracy: 1, "\(card.identifier) isn't the same size")
        XCTAssertEqual(card.frame.width, cardFrame.width, accuracy: 1, "\(card.identifier) isn't the same width")
    }

    /// The cards under the top one show only their edges, never their words below it (Tracy, 2026-11-24).
    func assertOnlyEdgesPeek(under top: XCUIElement, in app: XCUIApplication) {
        let under = app.descendants(matching: .any).matching(identifier: "coachDeck.under").allElementsBoundByIndex
        XCTAssertEqual(under.count, 2, "the next two cards don't peek out under the top one")
        for card in under {
            XCTAssertLessThanOrEqual(
                card.frame.maxY, top.frame.maxY + 2 * 12 + 1, "a card shows below the top one: \(card.frame)")
        }
    }

    /// 教练有话说 hangs under the squad card's trailing end (Tracy, 2026-11-24), with a dot while 毛头
    /// has a card I haven't seen, above the gift button when a gift waits; a tap opens 毛头's page.
    /// At night the column hangs under the pull cord's bulb, on the same page margin (Tracy,
    /// 2026-11-27).
    func testTheHomesCoachButtonOpensWhatTheCoachSaid() {
        continueAfterFailure = false
        for (folded, night) in [(true, false), (false, false), (true, true), (false, true)] {
            let app = launch(extra: ["-uitest-coach-gift"], folded: folded, night: night)
            let button = app.buttons["today.coachNews"]
            XCTAssertTrue(button.waitForExistence(timeout: Self.wait), "no 教练有话说 button")
            expectation(for: NSPredicate(format: "value == %@", "有新消息"), evaluatedWith: button)
            waitForExpectations(timeout: Self.wait)
            XCTAssertTrue(button.isHittable, "the 教练有话说 button is covered")
            let card = app.descendants(matching: .any).matching(identifier: "today.card").firstMatch
            XCTAssertGreaterThanOrEqual(button.frame.minY, card.frame.maxY, "the 教练有话说 button sits on the card")
            XCTAssertTrue(app.windows.firstMatch.frame.contains(button.frame), "the 教练有话说 button is off screen")
            let gift = app.buttons["today.gift"]
            XCTAssertTrue(gift.waitForExistence(timeout: Self.wait), "no gift button")
            XCTAssertGreaterThanOrEqual(gift.frame.minY, button.frame.maxY, "the gift button isn't under 教练有话说")
            XCTAssertEqual(gift.frame.midX, button.frame.midX, accuracy: 1, "the two buttons aren't one column")
            let screen = app.windows.firstMatch.frame
            XCTAssertEqual(button.frame.maxX, screen.maxX - 16, accuracy: 1, "the column isn't on the page margin")
            if night {
                let cord = app.buttons["today.lights"]
                XCTAssertTrue(cord.waitForExistence(timeout: Self.wait), "no pull cord at night")
                // The cord's frame takes in the 36 points it can be pulled down; its bulb rests above that.
                XCTAssertGreaterThanOrEqual(
                    button.frame.minY, cord.frame.maxY - 36, "the column isn't under the cord's bulb: \(cord.frame)")
            }
            let name = folded ? "120-home-coach-button-folded" : "121-home-coach-button"
            keepScreenshot(named: night ? name + "-night" : name)
            button.tap()
            XCTAssertTrue(
                self.card("board", in: app).waitForExistence(timeout: Self.wait), "the button didn't open 毛头's page")
            app.terminate()
        }
    }
}
