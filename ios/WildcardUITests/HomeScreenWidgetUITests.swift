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

        openGallery()

        let search = springboard.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: Self.wait), "no gallery search:\n\(tree)")
        search.tap()
        search.typeText("Wildcard")
        Thread.sleep(forTimeInterval: 2)
        log("searched")
        let named = NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS %@", "Wildcard", "外卡")
        let found = springboard.descendants(matching: .any).matching(named)
        _ = found.firstMatch.waitForExistence(timeout: Self.wait)
        attachTree("70-home-widget-search-tree")
        // The gallery's row for the app, not its icon behind the gallery.
        let entry = found.allElementsBoundByIndex.first {
            $0.elementType != .icon && $0.frame.width > 0 && $0.isHittable
        }
        print(
            "home-widget: found \(found.allElementsBoundByIndex.map { "\($0.elementType.rawValue) \($0.frame) \($0.label)" })"
        )
        let row = try XCTUnwrap(entry, "the app isn't in the widget gallery:\n\(tree)")
        row.tap()
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

    /// The widget gallery: 长按桌面 until the icons jiggle, then 编辑 › 添加小组件.
    private func openGallery() {
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
    }

    private var tree: String { String(springboard.debugDescription.prefix(6000)) }

    private func log(_ step: String) {
        print("===== home-widget: \(step) =====\n\(tree)")
    }

    private func attachTree(_ name: String) {
        let tree = XCTAttachment(string: springboard.debugDescription)
        tree.name = name
        tree.lifetime = .keepAlways
        add(tree)
        print("===== \(name) =====\n\(springboard.debugDescription)")
    }

    private func keepScreenshot(named name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
