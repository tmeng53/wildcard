import XCTest

/// A teammate moves the squad to the track while I'm away: opening the home drops the squad onto
/// the track, then the notice drops from the top saying who moved it. It stays on one line, whole
/// on screen, and a swipe up puts it away. Screenshots are kept for review.
@MainActor
final class NoticeUITests: XCTestCase {
    /// Slow CI simulators can take many seconds to show a screen; a real failure still fails.
    private static let wait: TimeInterval = 30

    func testASceneMoveIsTold() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon",
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

        banner.swipeUp()
        waitFor(banner, "exists == false", "a swipe up didn't put the notice away", timeout: Self.wait)
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
