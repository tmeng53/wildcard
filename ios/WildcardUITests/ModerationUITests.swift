import XCTest

/// 举报 and 拉黑 on the sample squad (App Review 1.2): the 「…」 on a teammate's post, each asking
/// first, and 设置 › 已拉黑 with 解除.
@MainActor
final class ModerationUITests: XCTestCase {
    private static let wait: TimeInterval = 30

    /// 举报 asks 举报这条动态？ in the menu, then the post leaves 动态.
    func testReportATeammatesPost() {
        let app = launch(["-tab", "feed"])
        openTeammateMenu(in: app)
        let posts = teammatePosts(in: app)
        app.buttons["post.report"].tap()
        let confirm = app.buttons["post.report.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: Self.wait), "举报 didn't ask first")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '举报这条动态？'")).firstMatch
                .exists, "the menu doesn't ask 举报这条动态？")
        assertOnScreen(confirm, in: app)
        settle()
        keepScreenshot(named: "120-feed-report-confirm")
        confirm.tap()
        waitForFewer(than: posts, in: app, "the reported post is still in 动态")
    }

    /// 拉黑 asks with what it does, then the teammate's posts leave 动态.
    func testBlockATeammate() {
        let app = launch(["-tab", "feed"])
        openTeammateMenu(in: app)
        let posts = teammatePosts(in: app)
        let block = app.buttons["post.block"]
        XCTAssertTrue(block.label.hasPrefix("拉黑 "), "拉黑 doesn't name the teammate: \(block.label)")
        block.tap()
        let confirm = app.buttons["post.block.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: Self.wait), "拉黑 didn't ask first")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '你们互相看不到对方的动态和评论'"))
                .firstMatch.exists, "the menu doesn't say what 拉黑 does")
        assertOnScreen(confirm, in: app)
        settle()
        keepScreenshot(named: "121-feed-block-confirm")
        confirm.tap()
        waitForFewer(than: posts, in: app, "the blocked teammate's posts are still in 动态")
        settle()
        keepScreenshot(named: "122-feed-after-block")
    }

    /// 设置 › 已拉黑 lists Coco; 解除 takes her off.
    func testBlockedList() {
        let app = launch(["-tab", "me", "-uitest-blocked"])
        let settings = app.buttons["me.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: Self.wait), "no 设置 on 我")
        settings.tap()
        let row = app.buttons["me.blocked"]
        let page = app.descendants(matching: .any).matching(identifier: "settings.page").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: Self.wait), "设置 didn't open")
        var swipes = 0
        while !row.isHittable, swipes < 6 {
            page.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(row.isHittable, "no 已拉黑 in 设置")
        settle()
        keepScreenshot(named: "123-settings-blocked-row")
        row.tap()
        let member = app.descendants(matching: .any).matching(identifier: "blocked.member").firstMatch
        XCTAssertTrue(member.waitForExistence(timeout: Self.wait), "已拉黑 doesn't list Coco")
        let unblock = app.buttons["blocked.unblock"].firstMatch
        assertOnScreen(unblock, in: app)
        settle()
        keepScreenshot(named: "124-settings-blocked")
        unblock.tap()
        waitFor(member, "exists == false", "解除 didn't take Coco off the list")
    }

    /// How many teammates' posts 动态 has laid out.
    private func teammatePosts(in app: XCUIApplication) -> Int {
        app.descendants(matching: .any).matching(identifier: "post.moderate").count
    }

    /// Asked afresh each time, since a query's first match moves on to the next card.
    private func waitForFewer(than count: Int, in app: XCUIApplication, _ message: String) {
        let deadline = Date.now.addingTimeInterval(Self.wait)
        while teammatePosts(in: app) >= count, Date.now < deadline {
            RunLoop.current.run(until: Date.now.addingTimeInterval(0.5))
        }
        XCTAssertLessThan(teammatePosts(in: app), count, message)
    }

    /// Scrolls to a teammate's 「…」 and opens 举报 and 拉黑.
    private func openTeammateMenu(in app: XCUIApplication) {
        continueAfterFailure = false
        let moderate = app.descendants(matching: .any).matching(identifier: "post.moderate").firstMatch
        let feed = app.scrollViews.firstMatch
        XCTAssertTrue(feed.waitForExistence(timeout: Self.wait), "no 动态")
        let tabBarTop = tabButton("tab.feed", in: app).frame.minY
        var drags = 0
        while drags < 24, !(moderate.exists && moderate.isHittable && moderate.frame.maxY <= tabBarTop) {
            let from = feed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -240)))
            drags += 1
        }
        XCTAssertTrue(moderate.isHittable, "a teammate's post shows no 「…」")
        moderate.tap()
        XCTAssertTrue(app.buttons["post.report"].waitForExistence(timeout: Self.wait), "「…」 has no 举报")
        XCTAssertTrue(app.buttons["post.block"].exists, "「…」 has no 拉黑")
        settle()
        keepScreenshot(named: "119-feed-moderation-menu")
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments +=
            [
                "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon",
            ] + extra
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        return app
    }

    /// Lets springs settle before a screenshot.
    private func settle() {
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Whole inside the window.
    private func assertOnScreen(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(
            app.windows.firstMatch.frame.contains(element.frame), "\(element.identifier) is cut off: \(element.frame)")
    }
}
