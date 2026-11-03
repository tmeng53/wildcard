import XCTest

/// The squad celebrating together on the home, the way a person meets it on opening the app:
/// 人浪 when the week's goal is reached, 叠罗汉 when two teammates ran today, 撞头 when I trained
/// too. Frames of each are kept, named with when each was taken, for review; the home's card and
/// the 打卡 button stay in place throughout.
@MainActor
final class TogetherUITests: XCTestCase {
    /// Slow CI simulators can take many seconds to show a screen; a real failure still fails.
    private static let wait: TimeInterval = 30

    func testTheWave() {
        celebrate("wave", frames: "61-wave")
    }

    func testTheStack() {
        celebrate("stack", frames: "62-stack")
    }

    func testTheBump() {
        celebrate("bump", frames: "63-bump")
    }

    private func celebrate(_ kind: String, frames name: String) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon",
            "-today.cardPage", "0", "-uitest-together", kind,
        ]
        app.launch()
        let card = app.descendants(matching: .any).matching(identifier: "today.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: Self.wait), "今天 never appeared")
        let opened = Date()
        for frame in 0..<16 {
            let after = Int(Date().timeIntervalSince(opened) * 1000)
            keepScreenshot(named: String(format: "\(name)-%02d-%05dms", frame, after))
            Thread.sleep(forTimeInterval: 0.35)
        }
        XCTAssertTrue(card.isHittable, "the squad card went away during the celebration")
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
