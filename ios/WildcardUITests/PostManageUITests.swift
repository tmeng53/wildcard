import XCTest

/// The member's own posts in 动态 on the sample squad: the 「…」 on them, and its 编辑 and 删除.
@MainActor
final class PostManageUITests: XCTestCase {
    private static let wait: TimeInterval = 30
    /// More than the sample squad's posts need to reach mine.
    private static let maxSwipes = 24

    /// 编辑 opens the compose page as posted; 保存 shows the new line on the card.
    func testEditMyPost() {
        let app = launch(language: "zh-Hans")
        let manage = openMenuOnMyPost(in: app)
        app.buttons["post.edit"].tap()

        let save = app.buttons["compose.post"]
        XCTAssertTrue(save.waitForExistence(timeout: Self.wait), "编辑 didn't open the compose page")
        XCTAssertEqual(save.label, "保存")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "compose.cover").firstMatch.exists,
            "the post's photo isn't on the compose page")
        XCTAssertTrue(app.buttons["compose.sport.strength"].isSelected, "the post's sport isn't picked")
        checkThePlaceTag(in: app)
        let caption = app.descendants(matching: .any).matching(identifier: "compose.caption").firstMatch
        // Below the one line, so the cursor goes to its end.
        caption.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).tap()
        caption.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20) + "扶手是我的好朋友")
        settle()
        keepScreenshot(named: "54-compose-editing")
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: Self.wait), "保存 didn't close the compose page")
        let edited = app.staticTexts.containing(NSPredicate(format: "label CONTAINS '扶手是我的好朋友'")).firstMatch
        XCTAssertTrue(edited.waitForExistence(timeout: Self.wait), "the card doesn't show the edited line")
        XCTAssertTrue(manage.exists, "the edited post lost its 「…」")
        settle()
        keepScreenshot(named: "55-feed-after-edit")
    }

    /// The post's gym on the ticket, its whole name shown while the row has room: tapping the
    /// name opens the map and leaves it on; only its cross takes it off (Tracy, 2026-11-13).
    private func checkThePlaceTag(in app: XCUIApplication) {
        let tag = app.buttons["compose.place"]
        let count = app.staticTexts["compose.count"]
        XCTAssertTrue(tag.waitForExistence(timeout: Self.wait), "the post's place isn't on the compose page")
        XCTAssertEqual(tag.label, "F45 Training Flatiron", "the tag doesn't name the post's place")
        let cross = app.buttons["pill.remove"]
        XCTAssertTrue(cross.exists, "the tag has no cross")
        XCTAssertLessThan(cross.frame.maxX, count.frame.minX, "the tag runs into the count")
        settle()
        keepScreenshot(named: "54a-compose-place-tagged")

        tag.tap()
        let search = app.descendants(matching: .any).matching(identifier: "place.search").firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: Self.wait), "tapping the name didn't open the map")
        app.buttons["place.cancel"].tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: Self.wait), "取消 didn't close the map")
        XCTAssertEqual(tag.label, "F45 Training Flatiron", "tapping the name took the place off")

        cross.tap()
        XCTAssertTrue(cross.waitForNonExistence(timeout: Self.wait), "the cross didn't take the place off")
        XCTAssertTrue(app.buttons["compose.place"].label.contains("添加位置"), "no 添加位置 after taking it off")
    }

    /// 删除 asks first, then the post is gone from 动态.
    func testDeleteMyPost() {
        let app = launch(language: "zh-Hans")
        let manage = openMenuOnMyPost(in: app)
        app.buttons["post.delete"].tap()
        // The menu asks in place: its header reads the question and what goes as one element.
        let confirm = app.buttons["post.delete.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: Self.wait), "删除 didn't ask first")
        let question = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '删掉这条动态？' AND label CONTAINS '队友的回应和评论也会一起删掉'"))
            .firstMatch
        XCTAssertTrue(question.exists, "the menu doesn't ask 删掉这条动态？ and say what goes")
        settle()
        keepScreenshot(named: "56-feed-delete-confirm")
        confirm.tap()
        waitFor(manage, "exists == false", "my post is still in 动态 after deleting it")
        XCTAssertFalse(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS '练腿日'")).firstMatch.exists,
            "the deleted post's line is still shown")
    }

    /// 存成绩卡 opens 存图's page on the card: a tap on the number, a number of the strip and the
    /// character changes it, the backdrops and 小队名 under it, all on the screen.
    func testSaveScoreCard() {
        let app = launch(language: "zh-Hans")
        openMenuOnMyPost(in: app)
        app.buttons["post.scoreCard"].tap()
        let save = app.buttons["savePicture.save"]
        XCTAssertTrue(save.waitForExistence(timeout: Self.wait), "存成绩卡 didn't open 存图's page")
        // The sheet's preview: SwiftUI folds the card's own container into it.
        let preview = app.descendants(matching: .any).matching(identifier: "savePicture.preview").firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: Self.wait), "存图's page doesn't show the card")
        // Only until the phone's first tap on a card, so a rerun on the same simulator has none.
        let hint = app.staticTexts["scoreCard.hint"]
        XCTAssertTrue(app.staticTexts["scoreCard.weekCount"].waitForExistence(timeout: Self.wait), "no 本周第 N 次")
        XCTAssertTrue(app.buttons["scoreCard.backdrop.photo.0"].isSelected, "the post's photo isn't the backdrop")
        XCTAssertTrue(app.buttons["scoreCard.backdrop.chart"].exists, "the post's chart isn't a backdrop")
        XCTAssertFalse(app.buttons["scoreCard.backdrop.map"].exists, "a post without a route offers 路线")
        settle()
        assertOnScreen(preview, in: app)
        assertOnScreen(save, in: app)
        keepScreenshot(named: "57-score-card")

        app.buttons["scoreCard.hero"].tap()
        waitFor(hint, "exists == false", "点数字和人物可以换 is still there after a tap")
        // Only the card's strip has buttons; the post's under the sheet is read-only.
        app.buttons["strip.maxHeartRate"].firstMatch.tap()
        app.buttons["scoreCard.character"].tap()
        app.buttons["scoreCard.backdrop.plain"].tap()
        XCTAssertTrue(app.buttons["scoreCard.backdrop.plain"].isSelected, "纯色 isn't picked")
        // Back to the chart, whose thumbnail draws without taking touches itself.
        app.buttons["scoreCard.backdrop.chart"].tap()
        XCTAssertTrue(app.buttons["scoreCard.backdrop.chart"].isSelected, "the chart can't be picked again")
        app.buttons["scoreCard.backdrop.plain"].tap()
        let squad = app.descendants(matching: .any).matching(identifier: "scoreCard.squad").firstMatch
        XCTAssertTrue(squad.waitForExistence(timeout: Self.wait), "the squad's name isn't on the card")
        app.switches.firstMatch.tap()
        waitFor(squad, "exists == false", "小队名 off still shows the squad's name")
        settle()
        assertOnScreen(app.buttons["savePicture.share"], in: app)
        keepScreenshot(named: "58-score-card-plain")
        app.buttons["savePicture.close"].tap()
        XCTAssertTrue(preview.waitForNonExistence(timeout: Self.wait), "关闭 didn't close the card")
    }

    /// My 练腿日's second page is its heart rate in zones on graphite: the warm-up and cool-down
    /// under 轻松 dimmed, and the zones' axis under the 「…」, not behind it.
    func testHeartRateCover() {
        continueAfterFailure = false
        let app = launch(language: "zh-Hans")
        let manage = app.descendants(matching: .any).matching(identifier: "post.manage").firstMatch
        let feed = app.scrollViews.firstMatch
        XCTAssertTrue(feed.waitForExistence(timeout: Self.wait), "no 动态")
        let tabBarTop = tabButton("tab.feed", in: app).frame.minY
        var drags = 0
        while drags < Self.maxSwipes, !(manage.exists && manage.isHittable && manage.frame.maxY + 240 <= tabBarTop) {
            let from = feed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -240)))
            drags += 1
        }
        XCTAssertTrue(manage.isHittable, "my post isn't on screen")
        let photos = app.descendants(matching: .any).matching(identifier: "feed.photos")
            .allElementsBoundByIndex.first { $0.frame.contains(manage.frame) }
        guard let photos else { return XCTFail("my post's cover isn't under its 「…」") }
        // One flick at the cover's middle now and then leaves the pager on the photo (red on
        // main 11-11 and 11-12, green between with nothing changed): drag level across the cover
        // just under the 「…」, which is on screen, and again while the chart isn't there.
        let chart = app.descendants(matching: .any).matching(identifier: "feed.chart").firstMatch
        let row = (manage.frame.midY - photos.frame.minY) / photos.frame.height
        var turns = 0
        while turns < 3, !chart.waitForExistence(timeout: turns == 0 ? 0 : 5) {
            let from = photos.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: row + 0.1))
            from.press(
                forDuration: 0.05,
                thenDragTo: photos.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: row + 0.1)),
                withVelocity: .default, thenHoldForDuration: 0)
            turns += 1
        }
        XCTAssertTrue(chart.waitForExistence(timeout: Self.wait), "my post's second page isn't its chart")
        settle()
        keepScreenshot(named: "52-feed-heart-rate-cover")
    }

    /// Scrolls to my post, the only one with a 「…」, and opens it on 编辑 and 删除.
    @discardableResult
    private func openMenuOnMyPost(in app: XCUIApplication) -> XCUIElement {
        continueAfterFailure = false
        let manage = app.descendants(matching: .any).matching(identifier: "post.manage").firstMatch
        let feed = app.scrollViews.firstMatch
        XCTAssertTrue(feed.waitForExistence(timeout: Self.wait), "no 动态")
        // Short drags, not swipes: a swipe's fling can stop with the 「…」 under the tab bar.
        let tabBarTop = tabButton("tab.feed", in: app).frame.minY
        var drags = 0
        while drags < Self.maxSwipes, !(manage.exists && manage.isHittable && manage.frame.maxY <= tabBarTop) {
            let from = feed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -240)))
            drags += 1
        }
        XCTAssertTrue(manage.isHittable, "my post shows no 「…」")
        assertClearOfTheTabBar(manage, in: app)
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "post.manage").count, 1,
            "a teammate's post shows 「…」")
        settle()
        keepScreenshot(named: "52-feed-my-post-manage")
        manage.tap()
        XCTAssertTrue(app.buttons["post.edit"].waitForExistence(timeout: Self.wait), "「…」 didn't open 编辑")
        XCTAssertTrue(app.buttons["post.delete"].exists, "「…」 has no 删除")
        settle()
        keepScreenshot(named: "53-feed-manage-menu")
        return manage
    }

    private func launch(language: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(\(language))", "-AppleLocale", language, "-uitest-no-push", "-uitest-noon", "-tab",
            "feed",
        ]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        return app
    }

    /// Fully on screen and above the floating tab bar, so nothing covers it.
    private func assertClearOfTheTabBar(_ element: XCUIElement, in app: XCUIApplication) {
        let screen = app.windows.firstMatch.frame
        XCTAssertTrue(screen.contains(element.frame), "\(element.identifier) is cut off: \(element.frame)")
        let bar = tabButton("tab.feed", in: app)
        XCTAssertLessThanOrEqual(element.frame.maxY, bar.frame.minY, "\(element.identifier) is under the tab bar")
    }

    /// Whole inside the window.
    private func assertOnScreen(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(
            app.windows.firstMatch.frame.contains(element.frame), "\(element.identifier) is cut off: \(element.frame)")
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
}
