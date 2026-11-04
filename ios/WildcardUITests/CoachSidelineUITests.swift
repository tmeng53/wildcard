import XCTest

/// The coach on the home's sideline, the way a member meets it (Tracy, 2026-11-04): 毛头 stands
/// there saying nothing by itself, and a tap opens its 简历 over 小队, with today's 战术板 line
/// on its small board; 返回 goes straight back home. Screenshots are kept for review.
@MainActor
final class CoachSidelineUITests: XCTestCase {
    /// Slow CI simulators can take many seconds to show a screen; a real failure still fails.
    private static let wait: TimeInterval = 30
    private static let line = "昨天三个人上场，我光在场边记笔记就累了。今天随缘，来了就算。"

    func testTappingTheCoachOpensItsResume() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon",
            "-today.cardPage", "0", "-uitest-coach",
        ]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }

        let coach = app.buttons["today.coach"]
        XCTAssertTrue(coach.waitForExistence(timeout: Self.wait), "no coach on the sideline")
        XCTAssertEqual(coach.label, "毛头")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertFalse(labeled(Self.line, in: app).exists, "the coach still says its line on the home")
        keepScreenshot(named: "61-coach-sideline")

        coach.tap()
        let resume = app.descendants(matching: .any).matching(identifier: "coach.resume").firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: Self.wait), "tapping the coach didn't open its 简历")
        let board = app.descendants(matching: .any).matching(identifier: "coach.resume.board").firstMatch
        XCTAssertTrue(board.waitForExistence(timeout: Self.wait), "the 简历 has no 战术板 board")
        XCTAssertTrue(board.label.contains(Self.line), "the board doesn't show today's line: \(board.label)")
        XCTAssertTrue(
            app.windows.firstMatch.frame.contains(board.frame), "the board runs off the screen: \(board.frame)")
        Thread.sleep(forTimeInterval: 0.6)
        keepScreenshot(named: "62-coach-resume-board")

        app.buttons["coach.resume.back"].tap()
        XCTAssertTrue(resume.waitForNonExistence(timeout: Self.wait), "返回 didn't close the 简历")
        XCTAssertTrue(app.buttons["today.checkin"].waitForExistence(timeout: Self.wait), "返回 didn't go back home")
        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: "squad.page").firstMatch.exists,
            "返回 left 小队 open")
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
