import XCTest

/// Checks in from 今天 the way a person does, and keeps screenshots for review. Photos come
/// from `-uitest-photos`, since UI tests can't drive the system photo picker reliably.
@MainActor
final class TodayUITests: XCTestCase {
    /// Slow CI simulators can take many seconds to show a screen; a real failure still fails.
    private static let wait: TimeInterval = 30

    /// 练了 with three photos: pick the minutes, write a caption, post, and land back on the scene
    /// with the squad bar ticked up.
    func testTrainedCheckIn() {
        let app = launch(language: "zh-Hans", photos: 3)
        _ = topCard(in: app)
        XCTAssertTrue(labeled("周三不练腿俱乐部", in: app).exists)
        XCTAssertTrue(labeled("14/24", in: app).exists)
        settle()
        keepScreenshot(named: "13-today")

        let checkIn = app.buttons["today.checkin"]
        XCTAssertEqual(checkIn.label, "打卡")
        checkIn.tap()
        for (kind, label) in [("trained", "训练"), ("healthyMeal", "健康餐"), ("cheatMeal", "放纵餐")] {
            let capsule = app.buttons["today.capsule.\(kind)"]
            XCTAssertTrue(capsule.waitForExistence(timeout: Self.wait), "no \(label) capsule")
            XCTAssertEqual(capsule.label, label)
        }
        settle()
        keepScreenshot(named: "14-today-checkin-menu")

        app.buttons["today.capsule.trained"].tap()
        let post = app.buttons["compose.post"]
        XCTAssertTrue(post.waitForExistence(timeout: Self.wait), "the compose page never opened")
        checkSportAndPickMinutes(in: app)
        let caption = app.descendants(matching: .any).matching(identifier: "compose.caption").firstMatch
        caption.tap()
        caption.typeText("晨跑 5 公里，腿还在")
        settle()
        keepScreenshot(named: "15-compose-trained")
        // With the keyboard up, the line stays in view and the bar stays clear of the status bar
        // (every Face ID iPhone's is at least 44 points tall).
        XCTAssertTrue(caption.isHittable, "the caption is hidden under the keyboard")
        XCTAssertGreaterThanOrEqual(post.frame.minY, 44, "发布 slid under the status bar: \(post.frame)")

        post.tap()
        // Frames of the check-in moment from when the scene is back, named with when each was
        // taken, for a recording of it.
        XCTAssertTrue(post.waitForNonExistence(timeout: Self.wait), "the compose page didn't close after posting")
        // The post goes out behind the scene, told on 打卡's spot.
        let outgoing = app.buttons["today.outgoing"]
        XCTAssertTrue(outgoing.waitForExistence(timeout: Self.wait), "nothing told the post was going out")
        let posted = Date()
        for frame in 0..<12 {
            let after = Int(Date().timeIntervalSince(posted) * 1000)
            keepScreenshot(named: String(format: "16-moment-%02d-%04dms", frame, after))
        }
        XCTAssertTrue(
            labeled("15/24", in: app).waitForExistence(timeout: Self.wait), "the squad's score didn't tick up to 15/24")
        // Let the cheer play out before the shot.
        Thread.sleep(forTimeInterval: 1.2)
        // The caption stays in the post: no bubble over my head.
        let shownCaption = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "晨跑 5 公里")).firstMatch
        XCTAssertFalse(shownCaption.exists && shownCaption.isHittable, "the caption showed on the scene")
        keepScreenshot(named: "16-today-trained-payoff")
        tapMeInMyKit(in: app)

        // 已发出 gives 打卡 its spot back.
        XCTAssertTrue(checkIn.waitForExistence(timeout: Self.wait), "打卡 didn't come back after 已发出")
        checkIn.tap()
        XCTAssertTrue(app.buttons["today.capsule.trained"].waitForExistence(timeout: Self.wait))
        XCTAssertFalse(app.buttons["today.capsule.disclaimer"].exists, "打卡 still offers a 请假条")
        settle()
        keepScreenshot(named: "17-today-checkin-menu-after-training")
    }

    /// The squad card's second page: my week, Monday to Sunday.
    func testMyWeekPage() {
        let app = launch(language: "zh-Hans", photos: 0, cardPage: nil)
        _ = topCard(in: app)
        let mine = app.buttons["squadcard.page.mine"]
        XCTAssertTrue(mine.waitForExistence(timeout: Self.wait), "no dot for my week")
        mine.tap()
        XCTAssertTrue(labeled("我的一周", in: app).waitForExistence(timeout: Self.wait), "my week never showed")
        settle()
        keepScreenshot(named: "13-today-my-week")
        // Tapping a day shows its line under the calendar.
        pickADayNotToday(in: app)
        settle()
        keepScreenshot(named: "13b-today-my-week-picked")
        // Leave the card as the other tests expect it.
        app.buttons["squadcard.page.squad"].tap()
    }

    func testTodayInEnglish() {
        let app = launch(language: "en", photos: 0)
        _ = topCard(in: app)
        XCTAssertTrue(labeled("Skip Leg Day Club", in: app).exists)
        XCTAssertEqual(app.buttons["today.checkin"].label, "Check in")
        settle()
        keepScreenshot(named: "20-today-en")
    }

    /// `cardPage` pins the squad card to its first page, since the card reopens where it was
    /// left; pass nil to let the test swipe it. The card is pinned open (folding is
    /// `TodayCapsuleUITests`').
    private func launch(language: String, photos: Int, extra: [String] = [], cardPage: Int? = 0) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments +=
            [
                "-uitest-photos", "\(photos)", "-AppleLanguages", "(\(language))", "-AppleLocale", language,
                "-uitest-no-push", "-uitest-noon",
            ] + (cardPage.map { ["-today.cardPage", "\($0)"] } ?? []) + ["-today.cardCollapsed", "0"] + extra
        app.launch()
        return app
    }

    /// Any element showing exactly `label`: the squad's name, a score.
    private func labeled(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// The squad card at the top.
    private func topCard(in app: XCUIApplication) -> XCUIElement {
        let card = app.descendants(matching: .any).matching(identifier: "today.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: Self.wait), "今天 never appeared")
        return card
    }

    /// Lets springs and blurs settle before a screenshot.
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

extension TodayUITests {
    /// The 练了 page's sport starts on the last one used; 其他 opens a ruler for any other number
    /// of minutes, which a swipe moves and the pill then shows; tapping the pill folds the ruler
    /// and keeps the length, and one tap on a usual length picks that instead.
    fileprivate func checkSportAndPickMinutes(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["compose.sport.run"].isSelected, "the last sport used (跑步) isn't picked")
        app.buttons["compose.minutes.other"].tap()
        let ruler = app.descendants(matching: .any).matching(identifier: "compose.minutes.ruler").firstMatch
        XCTAssertTrue(ruler.waitForExistence(timeout: Self.wait), "其他 didn't open the minutes ruler")
        XCTAssertEqual(ruler.value as? String, "60", "the ruler doesn't start on 60 minutes")
        ruler.swipeLeft()
        settle()
        XCTAssertNotEqual(ruler.value as? String, "60", "swiping the ruler didn't change the minutes")
        keepScreenshot(named: "15-compose-minutes-other")
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(ruler.frame), "the minutes ruler is cut off: \(ruler.frame)")
        let other = app.buttons["compose.minutes.other"]
        let ruled = ruler.value as? String ?? "?"
        XCTAssertTrue(other.label.contains(ruled), "the 其他 pill doesn't show the ruled length: \(other.label)")
        other.tap()
        XCTAssertTrue(ruler.waitForNonExistence(timeout: Self.wait), "tapping the pill didn't fold the ruler")
        // A swipe that stops on a usual length hands it back to that pill.
        let usual = app.buttons["compose.minutes.\(ruled)"]
        XCTAssertTrue(
            usual.exists ? usual.isSelected : other.isSelected && other.label.contains(ruled),
            "folding the ruler dropped the ruled length (\(ruled)): \(other.label)"
        )
        app.buttons["compose.minutes.60"].tap()
        XCTAssertTrue(app.buttons["compose.minutes.60"].isSelected, "60 minutes isn't picked")
        XCTAssertFalse(other.isSelected, "其他 stayed picked after picking 60")
    }
}

/// Taps Monday, or Tuesday when Monday is today and so already picked, and checks the line under
/// the calendar follows it.
private func pickADayNotToday(in app: XCUIApplication) {
    let day = app.buttons["squadcard.day.0"].isSelected ? 1 : 0
    app.buttons["squadcard.day.\(day)"].tap()
    XCTAssertTrue(app.buttons["squadcard.day.\(day)"].isSelected, "the tapped day isn't picked")
    let line = app.descendants(matching: .any).matching(identifier: "squadcard.dayLine").firstMatch.label
    XCTAssertTrue(line.hasPrefix(day == 0 ? "周一" : "周二"), "the line isn't the tapped day's: \(line)")
}

extension TodayUITests {
    /// The cheer over, I hop into the sport's kit and train at it; a tap on me opens my own card
    /// with my today over it and nothing to pat, and a tap off it closes it.
    fileprivate func tapMeInMyKit(in app: XCUIApplication) {
        Thread.sleep(forTimeInterval: 2)
        keepScreenshot(named: "16b-today-in-kit")
        let myCharacter = app.buttons["today.me"]
        XCTAssertTrue(myCharacter.waitForExistence(timeout: Self.wait), "my character isn't on the scene")
        myCharacter.tap()
        let today = app.descendants(matching: .any).matching(identifier: "today.mateToday").firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: Self.wait), "tapping me didn't open my today")
        XCTAssertTrue(app.buttons["me.card"].waitForExistence(timeout: Self.wait), "tapping me didn't open my card")
        XCTAssertFalse(app.buttons["today.pat"].exists, "my own today offers 拍一拍")
        Thread.sleep(forTimeInterval: 0.6)
        keepScreenshot(named: "16c-today-tapped-me")
        tapOffPopup(above: today, in: app)
        XCTAssertTrue(today.waitForNonExistence(timeout: Self.wait), "a tap off my card left it open")
    }
}
