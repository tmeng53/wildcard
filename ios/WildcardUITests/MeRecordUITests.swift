import XCTest

/// 训练记录 on 我, on the in-memory member's 21 weeks.
extension MeUITests {
    /// 训练记录 under the tiles: 21 weeks of days, and a tap on one opens the popover over it.
    func testTrainingRecord() {
        let app = launch(language: "zh-Hans")
        let record = app.descendants(matching: .any).matching(identifier: "me.record").firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 30), "我 has no 训练记录")
        app.swipeUp()
        assertClearOfTabBar(record, in: app)
        let cells = app.buttons.matching(identifier: "me.record.cell")
        XCTAssertEqual(cells.count, 21 * 7, "the record isn't 21 weeks of days")
        XCTAssertTrue(record.frame.minX >= 0 && record.frame.maxX <= app.frame.maxX, "the record runs off the screen")
        settle()
        keepScreenshot(named: "40-me-record")
        // The record's first Thursday, 2026-06-18 in the sample, a day well inside the screen.
        cells.element(boundBy: 3).tap()
        let day = app.descendants(matching: .any).matching(identifier: "me.record.day").firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 5), "a tap on a day opened nothing")
        settle()
        keepScreenshot(named: "40-me-record-day")
    }
}
