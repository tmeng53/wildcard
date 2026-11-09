import XCTest

/// 设置 › 桌面小组件 on the in-memory member.
extension MeUITests {
    /// 设置 › 桌面小组件: the widgets drawn as the home screen shows them and the three steps, all
    /// inside the screen and clear of the tab bar once scrolled to.
    func testWidgetGuideShowsTheWidgetsAndSteps() {
        let app = launch(language: "zh-Hans")
        let settingsButton = app.buttons["me.settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 30))
        settingsButton.tap()
        let row = app.buttons["me.widgets"]
        XCTAssertTrue(row.waitForExistence(timeout: 30), "设置 has no 桌面小组件 row")
        row.tap()
        let previews = app.descendants(matching: .any)["widgetGuide.previews"]
        XCTAssertTrue(previews.waitForExistence(timeout: 30), "桌面小组件 never opened")
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(previews.frame), "the widgets spill out of the screen: \(previews.frame)")
        settle()
        keepScreenshot(named: "49-me-widget-guide")
        let last = app.descendants(matching: .any)["widgetGuide.step3"]
        XCTAssertTrue(last.waitForExistence(timeout: 10), "no third step")
        if !last.isHittable { app.swipeUp() }
        let tabBar = app.tabBars.firstMatch
        for number in 1...3 {
            let step = app.descendants(matching: .any)["widgetGuide.step\(number)"]
            XCTAssertTrue(step.exists, "no step \(number)")
            XCTAssertTrue(window.contains(step.frame), "step \(number) spills out: \(step.frame)")
            if tabBar.exists {
                XCTAssertFalse(step.frame.intersects(tabBar.frame), "step \(number) is under the tab bar")
            }
        }
    }
}
