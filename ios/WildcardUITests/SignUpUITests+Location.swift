import XCTest

/// 下雨天也有安排 (approximate location), step 5.
extension SignUpUITests {
    /// 下雨天也有安排: its sample and line, then 允许, which the sample allows, so the step says 已打开 and goes
    /// on with 下一步.
    func allowLocation(in app: XCUIApplication) {
        let allow = app.buttons["location.allow"]
        XCTAssertTrue(allow.waitForExistence(timeout: Self.wait), "打开大概位置 never appeared")
        let purpose = app.descendants(matching: .any)["location.purpose"]
        XCTAssertTrue(purpose.exists, "no line on what the place is for")
        XCTAssertLessThanOrEqual(purpose.frame.maxY, allow.frame.minY, "允许 covers the line")
        settle()
        keepScreenshot(named: "44f-signup-location")
        allow.tap()
        let done = app.buttons["location.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.wait), "允许 didn't say 已打开")
        XCTAssertTrue(app.descendants(matching: .any)["location.allowed"].exists, "no 已打开 line")
        settle()
        keepScreenshot(named: "44g-signup-location-allowed")
        done.tap()
    }
}
