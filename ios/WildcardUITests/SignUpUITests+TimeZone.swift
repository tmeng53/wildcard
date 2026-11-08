import XCTest

extension SignUpUITests {
    /// Checks 比赛时区 starts on the phone's zone, then picks one from the searchable list.
    func pickSquadTimeZone(searching city: String, in app: XCUIApplication) {
        let row = app.buttons["squad.timeZone"]
        if !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: Self.wait), "no 比赛时区 under 小队目标")
        row.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: Self.wait), "比赛时区 has no search")
        settle()
        keepScreenshot(named: "42c-signup-squad-time-zone-list")
        search.tap()
        search.typeText(city)
        let zone = app.buttons["squad.timeZone.Asia/\(city)"]
        XCTAssertTrue(zone.waitForExistence(timeout: Self.wait), "searching \(city) finds no zone")
        zone.tap()
        XCTAssertTrue(row.waitForExistence(timeout: Self.wait), "picking a zone didn't close the list")
        XCTAssertTrue(row.label.contains(city), "the row doesn't show the zone picked: \(row.label)")
        settle()
        keepScreenshot(named: "42d-signup-squad-time-zone")
    }
}
