import XCTest

/// Checks in from 今天 the way a person does, and keeps screenshots for review. Photos come
/// from `-uitest-photos`, since UI tests can't drive the system photo picker reliably.
@MainActor
final class TodayUITests: XCTestCase {
    /// 练了 with three photos: pick a cover, write a caption, post, and land back on the scene
    /// with the squad bar ticked up. Afterwards 免责 is greyed out for the day.
    func testTrainedCheckIn() {
        let app = launch(language: "zh-Hans", photos: 3)
        let card = topCard(in: app)
        XCTAssertTrue(card.label.contains("周三不练腿俱乐部"))
        XCTAssertTrue(card.label.contains("14/22"))
        XCTAssertTrue(card.label.contains("今天 3 人练了"))
        settle()
        keepScreenshot(named: "13-today")

        let checkIn = app.buttons["today.checkin"]
        XCTAssertEqual(checkIn.label, "打卡")
        checkIn.tap()
        waitForLabel(of: checkIn, "label == %@", "收起", "the check-in button didn't turn into 收起")
        for (meaning, label) in [("trained", "练了"), ("fresh", "健康餐"), ("indulgence", "放纵餐"), ("disclaimer", "免责")] {
            let capsule = app.buttons["today.capsule.\(meaning)"]
            XCTAssertTrue(capsule.waitForExistence(timeout: 2), "no \(label) capsule")
            XCTAssertEqual(capsule.label, label)
        }
        settle()
        keepScreenshot(named: "14-today-burst")

        app.buttons["today.capsule.trained"].tap()
        let post = app.buttons["compose.post"]
        XCTAssertTrue(post.waitForExistence(timeout: 3), "the compose page never opened")
        XCTAssertTrue(app.buttons["compose.sport.run"].isSelected, "the last sport used (跑步) isn't picked")
        app.buttons["compose.photo.2"].tap()
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
        let bubble = app.descendants(matching: .any).matching(identifier: "today.bubble").firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 5), "no payoff bubble after posting")
        XCTAssertTrue(bubble.label.contains("晨跑 5 公里，腿还在"))
        waitForLabel(of: card, "label CONTAINS %@", "15/22", "the squad bar didn't tick up to 15/22")
        XCTAssertTrue(card.label.contains("今天 4 人练了"))
        // Let the cheer play out before the shot.
        Thread.sleep(forTimeInterval: 1.2)
        keepScreenshot(named: "16-today-trained-payoff")

        checkIn.tap()
        let disclaimer = app.buttons["today.capsule.disclaimer"]
        XCTAssertTrue(disclaimer.waitForExistence(timeout: 2))
        disclaimer.tap()
        XCTAssertFalse(app.buttons["disclaimer.post"].waitForExistence(timeout: 1), "免责 opened after training")
        settle()
        keepScreenshot(named: "17-today-disclaimer-unavailable")
    }

    /// 免责: pick a line on offer, type a reason, pick a style for lines from it, take another
    /// line, bring the typed words back, post, and the line lands on the scene without moving
    /// the squad bar.
    func testDisclaimer() {
        let app = launch(language: "zh-Hans", photos: 0)
        let card = topCard(in: app)
        let field = openDisclaimer(in: app)
        let close = app.buttons["disclaimer.close"]
        let post = app.buttons["disclaimer.post"]
        let source = app.staticTexts["disclaimer.source"]
        XCTAssertGreaterThanOrEqual(close.frame.minY, 44, "the header slid under the status bar: \(close.frame)")
        // The page opens on writing the reason, with nothing to post yet.
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2), "the keyboard isn't up")
        XCTAssertEqual(field.placeholderValue, "为什么没练？")
        XCTAssertEqual(source.label, "灵感：随机")
        XCTAssertFalse(post.isEnabled, "an empty excuse can be posted")

        field.typeText("deadline")
        settle()
        // With the keyboard up, the excuse and 发布 stay in view.
        XCTAssertTrue(field.isHittable, "the excuse is hidden under the keyboard")
        XCTAssertTrue(post.isHittable, "发到小队 is hidden under the keyboard")
        XCTAssertFalse(app.buttons["disclaimer.restore"].exists, "用回我写的 shows before anything replaced the words")

        // Picking a style writes lines from the typed words, and the first lands at once.
        let funny = app.buttons["disclaimer.style.funny"]
        funny.tap()
        let first = app.buttons["disclaimer.draft.1"]
        XCTAssertTrue(first.waitForExistence(timeout: 3), "picking a style offered no lines")
        settle()
        XCTAssertTrue(funny.isSelected, "the picked style isn't marked")
        XCTAssertEqual(source.label, "灵感：deadline")
        XCTAssertEqual(field.value as? String, first.label, "picking a style didn't put its first line up")
        XCTAssertTrue(first.isSelected, "the line in the excuse isn't marked")
        keepScreenshot(named: "18-disclaimer-styled")

        // Another line on offer replaces it; 用回我写的 brings the typed words back.
        let second = app.buttons["disclaimer.draft.2"]
        second.tap()
        settle()
        XCTAssertEqual(field.value as? String, second.label)
        app.buttons["disclaimer.restore"].tap()
        settle()
        XCTAssertEqual(field.value as? String, "deadline")

        // 换一组 offers new lines and puts the first up.
        app.buttons["disclaimer.again"].tap()
        settle()
        let line = field.value as? String ?? ""
        XCTAssertNotEqual(line, "deadline", "换一组 left the typed words")
        XCTAssertEqual(line, app.buttons["disclaimer.draft.1"].label)
        // 编辑 starts typing again, and the count shows while typing.
        app.buttons["disclaimer.edit"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2), "编辑 didn't start typing")
        XCTAssertEqual(
            app.staticTexts["disclaimer.count"].label, "\(line.count)/40", "the count doesn't match the excuse")
        post.tap()

        let bubble = app.descendants(matching: .any).matching(identifier: "today.bubble").firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 5), "no payoff bubble after the 免责声明")
        XCTAssertTrue(bubble.label.contains(line))
        XCTAssertTrue(card.label.contains("14/22"), "a 免责声明 moved the squad bar")
        settle()
        keepScreenshot(named: "19-today-disclaimer-posted")
    }

    /// The excuse shows exactly what will be posted: Return finishes editing, and typing stops
    /// at 40 characters.
    func testDisclaimerFieldFitsTheLine() {
        let app = launch(language: "zh-Hans", photos: 0)
        _ = topCard(in: app)
        let field = openDisclaimer(in: app)
        field.typeText(String(repeating: "a", count: 30) + "\n")
        settle()
        XCTAssertEqual(field.value as? String, String(repeating: "a", count: 30), "Return went into the excuse")
        XCTAssertEqual(app.keyboards.count, 0, "Return didn't finish editing")
        // 编辑 puts the cursor after the line (a tap on the text could land anywhere in it).
        app.buttons["disclaimer.edit"].tap()
        field.typeText(String(repeating: "b", count: 20))
        settle()
        XCTAssertEqual(field.value as? String, String(repeating: "a", count: 30) + String(repeating: "b", count: 10))
    }

    /// A reason the writer won't joke about: the author sees the care line, and it can't be
    /// posted until the line changes.
    func testCareLine() {
        let app = launch(language: "zh-Hans", photos: 0, extra: ["-uitest-care"])
        _ = topCard(in: app)
        let field = openDisclaimer(in: app)
        field.typeText("不想活了")
        app.buttons["disclaimer.style.funny"].tap()

        XCTAssertTrue(app.buttons["disclaimer.care.call"].waitForExistence(timeout: 3), "no care line")
        XCTAssertEqual(app.buttons["disclaimer.care.call"].label, "打给 988")
        XCTAssertEqual(app.buttons["disclaimer.care.text"].label, "发短信给 988")
        XCTAssertTrue(app.staticTexts["有紧急危险请直接打 911。"].exists)
        XCTAssertEqual(field.value as? String, "不想活了", "the writer put a joke in anyway")
        XCTAssertFalse(app.buttons["disclaimer.style.funny"].exists, "the styles still show beside the care line")
        XCTAssertFalse(app.buttons["disclaimer.draft.1"].exists, "the writer offered jokes anyway")
        XCTAssertFalse(app.buttons["disclaimer.post"].isEnabled, "a blocked reason can be posted")
        settle()
        keepScreenshot(named: "21-disclaimer-care")

        app.buttons["disclaimer.edit"].tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "好累")
        XCTAssertTrue(app.buttons["disclaimer.post"].isEnabled, "a changed line can't be posted")
        XCTAssertFalse(app.buttons["disclaimer.care.call"].exists, "the care line stayed after a new line")
    }

    /// Opens the 免责声明 page from the burst and returns its excuse field.
    private func openDisclaimer(in app: XCUIApplication) -> XCUIElement {
        app.buttons["today.checkin"].tap()
        let capsule = app.buttons["today.capsule.disclaimer"]
        XCTAssertTrue(capsule.waitForExistence(timeout: 2))
        capsule.tap()
        let field = app.descendants(matching: .any).matching(identifier: "disclaimer.field").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3), "the 免责声明 page never opened")
        return field
    }

    /// 健康餐: the same compose page, with its own placeholder and no sport row.
    func testHealthyMealCompose() {
        let app = launch(language: "zh-Hans", photos: 1)
        _ = topCard(in: app)
        app.buttons["today.checkin"].tap()
        let capsule = app.buttons["today.capsule.fresh"]
        XCTAssertTrue(capsule.waitForExistence(timeout: 2))
        capsule.tap()
        let caption = app.descendants(matching: .any).matching(identifier: "compose.caption").firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 3), "the compose page never opened")
        XCTAssertEqual(caption.placeholderValue, "这顿很自律…")
        XCTAssertFalse(app.buttons["compose.sport.run"].exists, "a meal shows the sport row")
        XCTAssertFalse(app.buttons["compose.photo.1"].exists, "one photo shows a cover choice")
        settle()
        keepScreenshot(named: "22-compose-healthy-meal")
    }

    func testTodayInEnglish() {
        let app = launch(language: "en", photos: 0)
        XCTAssertTrue(topCard(in: app).label.contains("Skip Leg Day Club"))
        XCTAssertEqual(app.buttons["today.checkin"].label, "Check in")
        settle()
        keepScreenshot(named: "20-today-en")
    }

    private func launch(language: String, photos: Int, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments +=
            [
                "-uitest-photos", "\(photos)", "-AppleLanguages", "(\(language))", "-AppleLocale", language,
            ] + extra
        app.launch()
        return app
    }

    /// The top card, which VoiceOver reads as one element.
    private func topCard(in app: XCUIApplication) -> XCUIElement {
        let card = app.descendants(matching: .any).matching(identifier: "today.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "今天 never appeared")
        return card
    }

    /// Lets springs and blurs settle before a screenshot.
    private func settle() {
        Thread.sleep(forTimeInterval: 0.8)
    }

    /// Taps update the UI on the next frames; wait for the label instead of checking at once.
    private func waitForLabel(
        of element: XCUIElement, _ format: String, _ text: String, _ message: String,
        timeout: TimeInterval = 10
    ) {
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: format, text), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [changed], timeout: timeout), .completed, message)
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
