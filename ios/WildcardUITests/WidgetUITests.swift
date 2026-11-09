import XCTest

/// The home screen widgets on the sample squad, through the app's `-widgets` preview (UI tests
/// can't put a widget on the home screen): keeps screenshots for review against the approved
/// design, and checks every line stays inside its widget, in Chinese and in English.
@MainActor
final class WidgetUITests: XCTestCase {
    private static let wait: TimeInterval = 30

    func testWidgetsInChinese() {
        continueAfterFailure = false
        let app = launch(language: "zh-Hans")
        assertContentInside(app)
        keepScreenshot(named: "70-widgets")
    }

    func testWidgetsInEnglish() {
        continueAfterFailure = false
        let app = launch(language: "en")
        assertContentInside(app)
        keepScreenshot(named: "70-widgets-en")
    }

    private func launch(language: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(\(language))", "-AppleLocale", language, "-uitest-no-push", "-uitest-noon",
            "-widgets",
        ]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        return app
    }

    /// Each widget's text and its 打卡 sit inside the widget, so nothing is clipped at its edge.
    private func assertContentInside(_ app: XCUIApplication) {
        for name in [
            "widget.week", "widget.notice", "widget.squad", "widget.weekWorkout", "widget.squadWorkout",
        ] {
            let widget = app.otherElements[name]
            XCTAssertTrue(widget.waitForExistence(timeout: Self.wait), "\(name) didn't show")
            let frame = widget.frame
            for element in widget.descendants(matching: .any).allElementsBoundByIndex
            where !element.frame.isEmpty && (element.elementType == .staticText || element.elementType == .link) {
                XCTAssertTrue(
                    frame.contains(element.frame),
                    "\(name): 「\(element.label)」 spills out: \(element.frame) in \(frame)")
            }
        }
        XCTAssertTrue(app.links["widget.checkIn"].exists || app.buttons["widget.checkIn"].exists, "no 打卡 on 小队今天")
        // The capsule's run and its 打卡, on both widgets.
        for name in ["widget.weekWorkout", "widget.squadWorkout"] {
            let widget = app.otherElements[name]
            XCTAssertTrue(widget.descendants(matching: .any)["widget.workout"].exists, "\(name): no workout")
            XCTAssertTrue(widget.descendants(matching: .any)["widget.postWorkout"].exists, "\(name): no 打卡")
        }
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
