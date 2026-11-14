import XCTest

/// 设置 › 小队设置 on the in-memory member.
extension MeUITests {
    /// 我's 设置 opens 小队设置, the page 小队's gear opens, with 邀请队友 as its first row.
    func testSettingsOpenSquadSettingsWithTheInviteFirst() {
        let app = launch(language: "zh-Hans")
        let settingsButton = app.buttons["me.settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 30))
        settingsButton.tap()
        let row = app.buttons["me.squadSettings"]
        XCTAssertTrue(row.waitForExistence(timeout: 30), "设置 has no 小队设置 row")
        settle()
        keepScreenshot(named: "49c-me-settings-squad")
        row.tap()
        let invite = app.buttons["squad.preferences.invite"]
        XCTAssertTrue(invite.waitForExistence(timeout: 30), "小队设置 from 设置 has no 邀请队友")
        let zone = app.descendants(matching: .any)["squad.timeZone"]
        XCTAssertTrue(zone.exists, "小队设置 from 设置 has no 比赛时区")
        XCTAssertLessThan(invite.frame.minY, zone.frame.minY, "邀请队友 isn't 小队设置's first row")
        XCTAssertLessThanOrEqual(invite.frame.maxX, app.frame.maxX, "the 邀请队友 row runs off the screen")
        settle()
        keepScreenshot(named: "49d-me-squad-settings")
    }
}
