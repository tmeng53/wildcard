import XCTest

/// Places on 我 opened by their address (`wildcard://…`), as a button whose destination is data
/// opens them, on the in-memory member.
extension MeUITests {
    /// `wildcard://settings` opens 设置, `wildcard://feedback` 意见反馈 over it, and
    /// `wildcard://my-posts` 我的动态 in place of both.
    func testAddressesOpenSettingsFeedbackAndMyPosts() throws {
        let app = launch(language: "zh-Hans")
        XCTAssertTrue(app.buttons["me.settings"].waitForExistence(timeout: 30))
        let window = app.windows.firstMatch.frame
        let pages = [
            ("settings", "settings.page"), ("feedback", "feedback.page"), ("my-posts", "wall.page"),
        ]
        for (address, identifier) in pages {
            app.open(try XCTUnwrap(URL(string: "wildcard://\(address)")))
            let page = app.descendants(matching: .any)[identifier]
            XCTAssertTrue(page.waitForExistence(timeout: 30), "wildcard://\(address) never opened \(identifier)")
            XCTAssertTrue(window.intersects(page.frame), "\(identifier) is off screen: \(page.frame)")
            settle()
            keepScreenshot(named: "147-address-\(address)")
        }
    }
}
