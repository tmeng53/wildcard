import XCTest

/// 拍一拍 on the home, the way a person meets it: 小米 and 阿杰 patted me, so opening the home
/// plays 小米's pat and her bubble offers one back; I pat her back, then tap 豆豆 and pat her, and
/// tapping 豆豆 twice opens and closes her bubble.
/// Each bubble stays whole on screen, clear of the tab bar, and screenshots are kept for review.
@MainActor
final class PatUITests: XCTestCase {
    /// Slow CI simulators can take many seconds to show a screen; a real failure still fails.
    private static let wait: TimeInterval = 30

    func testPatsOnTheHome() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon",
            "-today.cardPage", "0", "-uitest-patted", "-uitest-bubble-hold",
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

        // 豆豆, mid-yoga: her status, then a pat; once patted, her button greys out.
        Thread.sleep(forTimeInterval: 3.5)
        mate("豆豆", in: app).tap()
        XCTAssertTrue(bubble.waitForExistence(timeout: Self.wait), "tapping 豆豆 showed no bubble")
        XCTAssertTrue(labeled("今天练了", in: app).exists, "豆豆's bubble doesn't say she trained today")
        expectOnScreen(bubble, pat, in: app)
        XCTAssertEqual(pat.label, "拍一拍")
        Thread.sleep(forTimeInterval: 0.6)
        keepScreenshot(named: "54-mate-status")
        pat.tap()
        Thread.sleep(forTimeInterval: 3.5)
        mate("豆豆", in: app).tap()
        XCTAssertTrue(bubble.waitForExistence(timeout: Self.wait), "tapping 豆豆 again showed no bubble")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "today.pat").firstMatch.label, "拍过了")
        Thread.sleep(forTimeInterval: 0.6)
        keepScreenshot(named: "55-mate-patted")
        // A second tap on the same teammate closes their bubble, which would otherwise stay up
        // for a minute here.
        mate("豆豆", in: app).tap()
        XCTAssertTrue(bubble.waitForNonExistence(timeout: Self.wait), "tapping 豆豆 again left the bubble up")
    }

    /// The bubble whole inside the window, below the status bar and above the tab bar, and its
    /// button tappable.
    private func expectOnScreen(_ bubble: XCUIElement, _ button: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        let frame = bubble.frame
        XCTAssertGreaterThanOrEqual(frame.minX, window.minX, "the bubble runs off the left: \(frame)")
        XCTAssertLessThanOrEqual(frame.maxX, window.maxX, "the bubble runs off the right: \(frame)")
        XCTAssertGreaterThanOrEqual(frame.minY, 44, "the bubble is under the status bar: \(frame)")
        let tab = app.buttons["tab.today"]
        XCTAssertTrue(tab.exists, "no tab bar under 今天")
        XCTAssertLessThanOrEqual(frame.maxY, tab.frame.minY, "the tab bar covers the bubble: \(frame)")
        XCTAssertTrue(button.isHittable, "the bubble's button can't be tapped")
    }

    private func mate(_ nickname: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(identifier: "today.mate").matching(NSPredicate(format: "label == %@", nickname))
            .firstMatch
    }

    /// Any element showing exactly `label`.
    private func labeled(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
