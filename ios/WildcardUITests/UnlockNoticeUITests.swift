import XCTest

/// The sample member's training has just opened DEUCE CLUB: 今天 drops the notice in, whole on
/// screen and on one line each for its title and detail, and a tap on it opens 我's character
/// editor inside the store. Screenshots are kept for review.
@MainActor
final class UnlockNoticeUITests: XCTestCase {
    /// Slow CI simulators can take many seconds to show a screen; a real failure still fails.
    private static let wait: TimeInterval = 30

    func testAStoreThatOpenedIsToldAndATapWalksIn() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon",
            "-uitest-bubble-hold",
            "-today.cardPage", "0", "-uitest-unlocked",
        ]
        app.launch()

        let banner = app.descendants(matching: .any).matching(identifier: "notice.banner").firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: Self.wait), "the notice never dropped in")
        XCTAssertTrue(banner.label.contains("DEUCE CLUB 开门了"), "the notice says \(banner.label)")
        XCTAssertTrue(banner.label.contains("网球练满 3 次"), "the notice says \(banner.label)")
        // Lets the drop's spring settle.
        Thread.sleep(forTimeInterval: 0.6)
        keepScreenshot(named: "96-notice-store-unlocked")

        let window = app.windows.firstMatch.frame
        let frame = banner.frame
        XCTAssertGreaterThanOrEqual(frame.minX, window.minX, "the notice runs off the left: \(frame)")
        XCTAssertLessThanOrEqual(frame.maxX, window.maxX, "the notice runs off the right: \(frame)")
        XCTAssertGreaterThanOrEqual(frame.minY, window.minY, "the notice runs off the top: \(frame)")
        // Two lines (title and detail) beside a 36-point icon: a wrapped one would make it taller.
        XCTAssertLessThan(frame.height, 90, "the notice wrapped: \(frame)")

        banner.tap()
        let back = app.descendants(matching: .any).matching(identifier: "editor.store.back").firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: Self.wait), "the tap didn't open DEUCE CLUB in the editor")
        keepScreenshot(named: "97-notice-unlock-opens-store")
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
