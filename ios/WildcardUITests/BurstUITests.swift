import XCTest

/// The 打卡 capsules, laid out by their own widths.
@MainActor
final class BurstUITests: XCTestCase {
    private static let wait: TimeInterval = 15

    /// The four capsules never touch each other or the button, in every language, at the
    /// default and a large text size.
    func testBurstCapsulesDoNotOverlap() {
        for language in ["zh-Hans", "zh-Hant", "en"] {
            for size in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityXL"] {
                let app = launch(language: language, size: size)
                app.buttons["today.checkin"].tap()
                _ = app.buttons["today.capsule.disclaimer"].waitForExistence(timeout: Self.wait)
                settle()
                let frames = ["trained", "healthyMeal", "cheatMeal", "disclaimer"].map { kind -> CGRect in
                    let capsule = app.buttons["today.capsule.\(kind)"]
                    XCTAssertTrue(capsule.waitForExistence(timeout: Self.wait), "no \(kind) capsule")
                    return capsule.frame
                }
                let frame = app.windows.firstMatch.frame
                let button = app.buttons["today.checkin"].frame
                for (first, one) in frames.enumerated() {
                    XCTAssertTrue(frame.contains(one), "\(language) \(size): capsule \(first) leaves the screen")
                    XCTAssertFalse(one.intersects(button), "\(language) \(size): capsule \(first) covers the button")
                    for (second, other) in frames.enumerated() where second > first {
                        XCTAssertFalse(
                            one.intersects(other), "\(language) \(size): capsules \(first) and \(second) overlap")
                    }
                }
                app.terminate()
            }
        }
    }

    private func launch(language: String, size: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-uitest-photos", "0", "-AppleLanguages", "(\(language))", "-AppleLocale", language,
            "-uitest-no-push", "-uitest-noon", "-today.cardPage", "0",
            "-UIPreferredContentSizeCategoryName", size,
        ]
        app.launch()
        return app
    }

    private func settle() { Thread.sleep(forTimeInterval: 1) }
}
