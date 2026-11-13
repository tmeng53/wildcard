import XCTest

/// 拍一拍 on the home, the way a person meets it: 小米 and 阿杰 patted me, so opening the home
/// plays 小米's pat and her bubble offers one back; I pat her back, then tap 豆豆, whose card
/// opens with her today and 拍一拍 over it, and pat her from there.
/// Each bubble and today stays whole on screen, and screenshots are kept for review.
@MainActor
final class PatUITests: XCTestCase {
    /// Slow CI simulators can take many seconds to show a screen; a real failure still fails.
    private static let wait: TimeInterval = 30

    func testPatsOnTheHome() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon",
            "-today.cardPage", "0", "-uitest-card-folded", "-uitest-patted", "-uitest-bubble-hold",
        ]
        app.launch()

        // 小米 pats me from where she stands; frames of it, named with when each was taken.
        let card = app.descendants(matching: .any).matching(identifier: "today.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: Self.wait), "今天 never appeared")
        let opened = Date()
        for frame in 0..<8 {
            let after = Int(Date().timeIntervalSince(opened) * 1000)
            keepScreenshot(named: String(format: "51-patted-%02d-%04dms", frame, after))
        }
        XCTAssertTrue(labeled("小米拍了拍你", in: app).waitForExistence(timeout: Self.wait), "no bubble from 小米")
        XCTAssertTrue(labeled("阿杰 也拍了拍你", in: app).exists, "the bubble doesn't name 阿杰 too")
        let bubble = app.descendants(matching: .any).matching(identifier: "today.patBubble").firstMatch
        let pat = app.buttons["today.pat"]
        expectOnScreen(bubble, pat, in: app)
        XCTAssertEqual(pat.label, "拍一拍")
        keepScreenshot(named: "52-patted-bubble")

        // I pat her back.
        pat.tap()
        let patted = Date()
        for frame in 0..<8 {
            let after = Int(Date().timeIntervalSince(patted) * 1000)
            keepScreenshot(named: String(format: "53-pat-back-%02d-%04dms", frame, after))
        }
        XCTAssertTrue(bubble.waitForNonExistence(timeout: Self.wait), "the bubble stayed up after patting")

        // 豆豆, mid-yoga: a tap opens her card with her today over it, and 拍一拍 there closes it
        // and plays the pat on the scene; once patted, the button greys out.
        Thread.sleep(forTimeInterval: 3.5)
        mate("豆豆", in: app).tap()
        let today = app.descendants(matching: .any).matching(identifier: "today.mateToday").firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: Self.wait), "tapping 豆豆 didn't open her today")
        XCTAssertTrue(app.buttons["me.card"].waitForExistence(timeout: Self.wait), "her card didn't open under it")
        XCTAssertTrue(labeled("今天训练", in: app).exists, "豆豆's today doesn't say she trained")
        XCTAssertFalse(bubble.exists, "a tap still raises a bubble over her head")
        expectOnScreen(today, pat, in: app)
        XCTAssertEqual(pat.label, "拍一拍")
        Thread.sleep(forTimeInterval: 0.6)
        keepScreenshot(named: "54-mate-today")
        pat.tap()
        XCTAssertTrue(today.waitForNonExistence(timeout: Self.wait), "拍一拍 didn't close her card")
        Thread.sleep(forTimeInterval: 0.8)
        keepScreenshot(named: "54b-mate-patted-on-scene")
        Thread.sleep(forTimeInterval: 3)
        mate("豆豆", in: app).tap()
        XCTAssertTrue(today.waitForExistence(timeout: Self.wait), "tapping 豆豆 again didn't open her today")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "today.pat").firstMatch.label, "拍过了")
        Thread.sleep(forTimeInterval: 0.6)
        keepScreenshot(named: "55-mate-patted")
        closePopup(today, in: app)
    }

    /// Whoever posted a meal last eats it on the home, and their today says so with their words:
    /// 小米 had a salad after her run, Leo a boba without training.
    func testTeammatesEatingTheirLatestPost() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon",
            "-today.cardPage", "0", "-uitest-card-folded", "-uitest-meals", "-uitest-bubble-hold",
        ]
        app.launch()
        let card = app.descendants(matching: .any).matching(identifier: "today.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: Self.wait), "今天 never appeared")
        Thread.sleep(forTimeInterval: 2)
        keepScreenshot(named: "56-meals-home")

        let today = app.descendants(matching: .any).matching(identifier: "today.mateToday").firstMatch
        let pat = app.buttons["today.pat"]
        for (nickname, status, words, shot) in [
            ("Leo", "在吃放纵餐", "奶茶续命", "57-meals-boba"), ("小米", "在吃健康餐", "练完来碗沙拉", "58-meals-salad"),
        ] {
            mate(nickname, in: app).tap()
            XCTAssertTrue(today.waitForExistence(timeout: Self.wait), "tapping \(nickname) didn't open their today")
            XCTAssertTrue(labeled(status, in: today).exists, "\(nickname)'s today doesn't say what she is eating")
            XCTAssertTrue(labeled(words, in: today).exists, "\(nickname)'s today doesn't show her words")
            expectOnScreen(today, pat, in: app)
            Thread.sleep(forTimeInterval: 0.6)
            keepScreenshot(named: shot)
            closePopup(today, in: app)
        }
    }

    /// The bubble or today strip whole inside the window, below the status bar and above the
    /// tab bar, and its button tappable.
    private func expectOnScreen(_ bubble: XCUIElement, _ button: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        let frame = bubble.frame
        XCTAssertGreaterThanOrEqual(frame.minX, window.minX, "it runs off the left: \(frame)")
        XCTAssertLessThanOrEqual(frame.maxX, window.maxX, "it runs off the right: \(frame)")
        XCTAssertGreaterThanOrEqual(frame.minY, 44, "it is under the status bar: \(frame)")
        let tab = app.buttons["tab.today"]
        if tab.exists {
            XCTAssertLessThanOrEqual(frame.maxY, tab.frame.minY, "the tab bar covers it: \(frame)")
        }
        XCTAssertTrue(button.isHittable, "its button can't be tapped")
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

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
