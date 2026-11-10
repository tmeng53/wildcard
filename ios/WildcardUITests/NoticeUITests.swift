import XCTest

/// The notice banner: a teammate moves the squad to the track while I'm away, so opening the home
/// drops the squad onto the track, then the notice drops from the top saying who moved it, on one
/// line, whole on screen, and a swipe up puts it away; and a comment told while I'm on 我 drops in
/// there. Screenshots are kept for review.
@MainActor
final class NoticeUITests: XCTestCase {
    /// Slow CI simulators can take many seconds to show a screen; a real failure still fails.
    private static let wait: TimeInterval = 30

    func testASceneMoveIsTold() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon",
            "-uitest-bubble-hold",
            "-today.cardPage", "0", "-uitest-scene-moved", "track",
        ]
        app.launch()

        let banner = app.descendants(matching: .any).matching(identifier: "notice.banner").firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: Self.wait), "the notice never dropped in")
        XCTAssertTrue(banner.label.contains("把小队搬到了跑道"), "the notice says \(banner.label)")
        // Lets the drop's spring settle.
        Thread.sleep(forTimeInterval: 0.6)
        keepScreenshot(named: "95-notice-scene-moved")

        let window = app.windows.firstMatch.frame
        let frame = banner.frame
        XCTAssertGreaterThanOrEqual(frame.minX, window.minX, "the notice runs off the left: \(frame)")
        XCTAssertLessThanOrEqual(frame.maxX, window.maxX, "the notice runs off the right: \(frame)")
        XCTAssertGreaterThanOrEqual(frame.minY, window.minY, "the notice runs off the top: \(frame)")
        // One line of 15-point type in a 36-point icon's capsule: a second line would make it taller.
        XCTAssertLessThan(frame.height, 70, "the notice wrapped: \(frame)")
        // Phones with a notch or the Dynamic Island (all taller than 800 points) keep 44 points or
        // more at the top; the island would hide the notice's title there. Screenshots never draw it.
        if window.height > 800 {
            XCTAssertGreaterThanOrEqual(frame.minY, 44, "the notice sits under the Dynamic Island: \(frame)")
        }

        banner.swipeUp()
        waitFor(banner, "exists == false", "a swipe up didn't put the notice away", timeout: Self.wait)
    }

    /// A teammate comments while I'm on 我: its banner drops in there, on glass with its 查看,
    /// whole on screen, and 查看 opens the post's own page.
    func testACommentToldWhileTheAppIsOpenDropsInOnAnyPage() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon",
            "-uitest-bubble-hold", "-uitest-live-comment",
        ]
        app.launch()
        tabButton("tab.me", in: app).tap()

        let banner = app.descendants(matching: .any).matching(identifier: "notice.banner").firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: Self.wait), "the comment's banner never dropped in on 我")
        XCTAssertTrue(banner.label.contains("阿杰"), "the notice says \(banner.label)")
        XCTAssertTrue(banner.label.contains("查看"), "the notice has no 查看: \(banner.label)")
        Thread.sleep(forTimeInterval: 0.6)
        keepScreenshot(named: "95-notice-comment-on-me")

        let window = app.windows.firstMatch.frame
        let frame = banner.frame
        XCTAssertGreaterThanOrEqual(frame.minX, window.minX, "the notice runs off the left: \(frame)")
        XCTAssertLessThanOrEqual(frame.maxX, window.maxX, "the notice runs off the right: \(frame)")
        XCTAssertLessThan(frame.height, 90, "the notice wrapped: \(frame)")
        if window.height > 800 {
            XCTAssertGreaterThanOrEqual(frame.minY, 44, "the notice sits under the Dynamic Island: \(frame)")
        }

        banner.tap()
        // 查看 opens the comment's post, its own page over 动态, which hides the tab bar. The sample
        // notice's post isn't in the sample feed, so that page says it is gone.
        let post = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'post.field' OR label == '这条动态不见了'")).firstMatch
        XCTAssertTrue(post.waitForExistence(timeout: Self.wait), "查看 didn't open the comment's post")
        waitFor(banner, "exists == false", "the banner stayed after its tap", timeout: Self.wait)
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
