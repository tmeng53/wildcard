import XCTest

/// The widget gallery as a member opens it (长按桌面 › 编辑 › 添加小组件 › 搜「外卡」), so the
/// `WildcardWidgets` extension itself starts: the system lists an app's widgets only once the
/// extension answers, so an extension that stops on launch (TestFlight 193: a widget name WidgetKit
/// can't take) leaves the app out of the gallery and every widget blank. `WidgetUITests` checks
/// the views through the app's preview; this checks the extension runs.
@MainActor
final class HomeScreenWidgetUITests: XCTestCase {
    private static let wait: TimeInterval = 20
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    func testTheGalleryListsTheWidgets() throws {
        continueAfterFailure = false
        // Installed and launched once, so the system knows its widgets.
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push"]
        app.launch()
        Thread.sleep(forTimeInterval: 3)
        app.terminate()
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        addTeardownBlock { @MainActor in XCUIDevice.shared.press(.home) }

        openGallery()
        let search = springboard.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: Self.wait), "no gallery search:\n\(tree)")
        search.tap()
        search.typeText("Wildcard")

        // The gallery's row for the app, not its icon on the home screen behind the gallery.
        let row = springboard.cells.matching(NSPredicate(format: "label == %@ OR label == %@", "Wildcard", "外卡"))
            .firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: Self.wait) && row.frame.width > 0,
            "the app's widgets aren't in the gallery, so its extension didn't start:\n\(tree)")
        row.tap()
        // The gallery's preview of the first widget, from the extension's snapshot.
        Thread.sleep(forTimeInterval: 6)
        keepScreenshot(named: "70-home-widget-gallery")
    }

    /// Jiggle mode by long-pressing an empty part of the home screen, then 编辑 › 添加小组件.
    private func openGallery() {
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62)).press(forDuration: 2)
        let edit = springboard.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: Self.wait), "the home screen didn't enter jiggle mode:\n\(tree)")
        edit.tap()
        let add = springboard.buttons["Add Widget"]
        XCTAssertTrue(add.waitForExistence(timeout: Self.wait), "no Add Widget:\n\(tree)")
        add.tap()
    }

    private var tree: String { String(springboard.debugDescription.prefix(6000)) }

    private func keepScreenshot(named name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
