import XCTest

/// 设置 › 生日 on the in-memory member.
extension MeUITests {
    /// 设置 › 生日: the cards open on 2000-01-01, a finger's drag on the year card turns it on this
    /// scrolling page (the page must not take the drag), and 保存 puts the day on the 设置 row.
    func testBirthdayTurnsByDragAndSaves() {
        let app = launch(language: "zh-Hans")
        let settingsButton = app.buttons["me.settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 30))
        settingsButton.tap()
        let row = app.buttons["me.birthday"]
        XCTAssertTrue(row.waitForExistence(timeout: 30), "设置 has no 生日 row")
        XCTAssertTrue(row.label.contains("未填"), "the row doesn't say 未填: \(row.label)")
        row.tap()
        let year = app.descendants(matching: .any)["birthday.year"]
        XCTAssertTrue(year.waitForExistence(timeout: 30), "生日 never opened")
        XCTAssertEqual(year.value as? String, "2000", "the birthday doesn't open on 2000")
        XCTAssertFalse(app.buttons["birthday.save"].isEnabled, "保存 is on before a card turned")
        let card = year.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        card.press(forDuration: 0.1, thenDragTo: card.withOffset(CGVector(dx: 0, dy: 80)))
        waitFor(year, "value != '2000'", "a finger's drag down doesn't turn the year back")
        settle()
        keepScreenshot(named: "48-me-birthday")
        let save = app.buttons["birthday.save"]
        waitFor(save, "isEnabled == true", "保存 stays off after the year turned")
        save.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["birthday.page"].waitForNonExistence(timeout: 30), "保存 didn't go back to 设置"
        )
        waitFor(row, "NOT (label CONTAINS '未填')", "the 设置 row still says 未填 after 保存")
    }
}
