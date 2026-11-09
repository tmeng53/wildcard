import XCTest

/// 外卡记录, opened from 训练记录's 全部数据 on the in-memory member.
extension MeUITests {
    /// 全部数据 pushes 外卡记录: 训练时间 first, then the streaks, 最常练, the totals and 和小队, each
    /// inside the screen; 存图 opens the picture's sheet.
    func testWildcardRecords() {
        let app = launch(language: "zh-Hans")
        let link = app.buttons["me.records"]
        XCTAssertTrue(link.waitForExistence(timeout: 30), "训练记录 has no 全部数据")
        app.swipeUp()
        link.tap()
        let hero = app.descendants(matching: .any).matching(identifier: "records.hero").firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 10), "外卡记录 has no 训练时间")
        XCTAssertTrue(app.staticTexts["晚七点运动"].exists, "训练时间 doesn't name the usual hour")
        XCTAssertTrue(hero.frame.minX >= 0 && hero.frame.maxX <= app.frame.maxX, "训练时间 runs off the screen")
        // The opening has played.
        Thread.sleep(forTimeInterval: 3)
        keepScreenshot(named: "95-records")
        app.swipeUp()
        let partner = app.descendants(matching: .any).matching(identifier: "records.partner").firstMatch
        XCTAssertTrue(partner.waitForExistence(timeout: 5), "和小队 has no 最佳搭档")
        app.swipeUp()
        assertClearOfTabBar(partner, in: app)
        settle()
        keepScreenshot(named: "96-records-squad")
        app.buttons["records.save"].tap()
        XCTAssertTrue(app.buttons["savePicture.save"].waitForExistence(timeout: 10), "存图 opened no sheet")
        settle()
        keepScreenshot(named: "97-records-save")
    }

    /// 外卡记录 in English.
    func testWildcardRecordsInEnglish() {
        let app = launch(language: "en")
        let link = app.buttons["me.records"]
        XCTAssertTrue(link.waitForExistence(timeout: 30), "训练记录 has no See all")
        app.swipeUp()
        link.tap()
        XCTAssertTrue(app.staticTexts["7 PM regular"].waitForExistence(timeout: 10), "训练时间 isn't in English")
        Thread.sleep(forTimeInterval: 3)
        keepScreenshot(named: "95-records-en")
    }
}
