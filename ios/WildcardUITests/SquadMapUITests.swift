import XCTest

/// 小队地图 on the sample squad: the map button left of the bell on 动态 pushes it; 今天 lists
/// today's tagged posts, a row puts that member's day alone on the map until ✕, and 常去 lists
/// the squad's places by how often it went. Screenshots are kept for review against the approved
/// design (frames ⑩ to ⑬).
@MainActor
final class SquadMapUITests: XCTestCase {
    private static let wait: TimeInterval = 30

    func testTheSquadMapShowsTodayAMemberAndRegulars() {
        continueAfterFailure = false
        let app = launch()
        let open = app.buttons["squadMap.open"]
        XCTAssertTrue(open.waitForExistence(timeout: Self.wait), "no map button on 动态")
        let bell = app.buttons["notices.bell"]
        XCTAssertTrue(bell.waitForExistence(timeout: Self.wait), "no bell on 动态")
        XCTAssertLessThan(open.frame.maxX, bell.frame.minX, "the map button isn't left of the bell")
        assertOnScreen(open, in: app)

        open.tap()
        let row = app.buttons["squadMap.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.wait), "今天 lists no tagged post")
        assertOnScreen(row, in: app)
        settle()
        keepScreenshot(named: "squad-map-today")

        // A row: that member's day alone, with ✕ back to everyone.
        row.tap()
        let post = app.buttons["squadMap.memberPost"].firstMatch
        XCTAssertTrue(post.waitForExistence(timeout: Self.wait), "the member's posts didn't show")
        let close = app.buttons["squadMap.closeMember"]
        XCTAssertTrue(close.exists, "no ✕ on the member's day")
        assertOnScreen(close, in: app)
        settle()
        keepScreenshot(named: "squad-map-member")
        close.tap()
        XCTAssertTrue(row.waitForExistence(timeout: Self.wait), "✕ didn't go back to 今天")

        // 常去: the squad's places, most visited first.
        app.segmentedControls.buttons.element(boundBy: 1).tap()
        let place = app.buttons["squadMap.oftenRow"].firstMatch
        XCTAssertTrue(place.waitForExistence(timeout: Self.wait), "常去 lists no place")
        XCTAssertGreaterThanOrEqual(app.buttons.matching(identifier: "squadMap.oftenRow").count, 2)
        assertOnScreen(place, in: app)
        settle()
        keepScreenshot(named: "squad-map-often")

        // A place opens its own page.
        place.tap()
        XCTAssertFalse(
            app.buttons["squadMap.oftenRow"].waitForExistence(timeout: 2) && place.isHittable,
            "the place's page didn't open")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon", "-tab",
            "feed",
        ]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        return app
    }

    private func assertOnScreen(_ element: XCUIElement, in app: XCUIApplication) {
        let screen = app.windows.firstMatch.frame
        XCTAssertTrue(screen.contains(element.frame), "\(element.identifier) is cut off: \(element.frame)")
    }

    private func settle() {
        Thread.sleep(forTimeInterval: 1.5)
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
