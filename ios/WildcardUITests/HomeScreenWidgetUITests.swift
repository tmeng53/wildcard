import XCTest

/// The widgets put on the simulator's home screen the way a member does (长按桌面 › 编辑 ›
/// 添加小组件 › 外卡), so the `WildcardWidgets` extension itself runs and draws: the gallery's
/// preview and the widget on the home screen. `WidgetUITests` checks the views through the
/// app's preview; this checks the extension starts and draws them.
@MainActor
final class HomeScreenWidgetUITests: XCTestCase {
    private static let wait: TimeInterval = 20
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    func testTheWidgetDrawsOnTheHomeScreen() throws {
        continueAfterFailure = false
        // Installed and launched once, so the system knows its widgets.
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push"]
        app.launch()
        Thread.sleep(forTimeInterval: 3)
        app.terminate()
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)

        // Jiggle mode: long-press an empty part of the home screen.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62)).press(forDuration: 2)
        log("after long press")
        let edit = springboard.buttons["Edit"]
        if edit.waitForExistence(timeout: Self.wait) {
            edit.tap()
            let add = springboard.buttons["Add Widget"]
            XCTAssertTrue(add.waitForExistence(timeout: Self.wait), "no Add Widget:\n\(tree)")
            add.tap()
        } else {
            let add = springboard.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Add")).firstMatch
            XCTAssertTrue(add.waitForExistence(timeout: Self.wait), "no Edit or Add button:\n\(tree)")
            add.tap()
        }
        Thread.sleep(forTimeInterval: 2)
        log("gallery")

        let search = springboard.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: Self.wait), "no gallery search:\n\(tree)")
        search.tap()
        search.typeText("Wildcard")
        Thread.sleep(forTimeInterval: 2)
        log("searched")
        var entry = springboard.cells.matching(NSPredicate(format: "label CONTAINS[c] %@", "Wildcard")).firstMatch
        if !entry.waitForExistence(timeout: 5) {
            entry = springboard.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS %@", "Wildcard", "外卡"))
                .element(boundBy: 1)
        }
        XCTAssertTrue(entry.waitForExistence(timeout: Self.wait), "the app isn't in the widget gallery:\n\(tree)")
        entry.tap()
        // The gallery's preview: the extension's snapshot of the sample squad.
        Thread.sleep(forTimeInterval: 8)
        keepScreenshot(named: "70-home-widget-gallery")
        log("gallery preview")

        let addWidget = springboard.buttons["Add Widget"]
        XCTAssertTrue(addWidget.waitForExistence(timeout: Self.wait), "no Add Widget in the preview:\n\(tree)")
        addWidget.tap()
        Thread.sleep(forTimeInterval: 2)
        XCUIDevice.shared.press(.home)
        // The timeline's read: the sample squad on a build without a backend.
        Thread.sleep(forTimeInterval: 12)
        keepScreenshot(named: "70-home-widget-added")
        log("home screen")
    }

    private var tree: String { String(springboard.debugDescription.prefix(6000)) }

    private func log(_ step: String) {
        print("===== home-widget: \(step) =====\n\(tree)")
    }

    private func keepScreenshot(named name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
