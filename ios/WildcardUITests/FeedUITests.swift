import XCTest

/// 动态 on the sample squad, the way a teammate uses it: react with an emoji from the bar, the
/// grid or by holding the card, watch it fly to the author's character, see who reacted, and
/// keep screenshots for review. Each check that the
/// content clears the floating tab bar runs where the screen has the most in it.
@MainActor
final class FeedUITests: XCTestCase {
    private static let wait: TimeInterval = 30
    /// More than the sample squad's posts need to reach the end.
    private static let maxSwipes = 24
    /// The 成绩条 under a cover, with room to spare.
    private static let stripHeight = 80.0

    func testReact() {
        continueAfterFailure = false
        let app = launch(language: "zh-Hans")
        let react = app.buttons.matching(identifier: "feed.react").firstMatch
        XCTAssertTrue(react.waitForExistence(timeout: Self.wait), "no post to react to")
        settle()
        assertClearOfTheTabBar(app.staticTexts["feed.title"], in: app)
        keepScreenshot(named: "40-feed")

        react.tap()
        let bar = app.buttons["feed.emoji.💪"]
        XCTAssertTrue(bar.waitForExistence(timeout: Self.wait), "the emoji bar didn't open")
        assertOnScreen(bar, in: app)
        settle()
        keepScreenshot(named: "41-feed-emoji-bar")

        // The emoji flies to the author's head and the character plays its move.
        bar.tap()
        for frame in 0..<12 {
            keepScreenshot(named: String(format: "42-feed-reacted-%02d", frame))
            Thread.sleep(forTimeInterval: 0.12)
        }
        waitFor(bar, "exists == false", "the emoji bar stayed open")
        XCTAssertEqual(react.label, "我的回应：💪", "my emoji isn't on my button")

        // Tapping the heads opens who reacted, right at the row.
        app.buttons.matching(identifier: "feed.reactions").firstMatch.tap()
        let who = app.descendants(matching: .any).matching(identifier: "feed.who").firstMatch
        XCTAssertTrue(who.waitForExistence(timeout: Self.wait), "who reacted didn't open")
        assertOnScreen(who, in: app)
        settle()
        keepScreenshot(named: "43-feed-who-reacted")
        tapOutside(who, in: app)
        waitFor(who, "exists == false", "who reacted stayed open")

        // The oldest posts scroll up clear of the tab bar: swipe until the last post is on
        // screen, as the list builds its cards as they come.
        let posts = app.descendants(matching: .any).matching(identifier: "feed.post")
        let tabBarTop = tabButton("tab.feed", in: app).frame.minY
        var swipes = 0
        let feed = app.scrollViews.firstMatch
        while swipes < Self.maxSwipes, posts.element(boundBy: posts.count - 1).frame.maxY > tabBarTop {
            feed.swipeUp()
            swipes += 1
        }
        settle()
        // Kept before the check, so a failure shows where the list stopped.
        keepScreenshot(named: "45-feed-end")
        assertClearOfTheTabBar(posts.element(boundBy: posts.count - 1), in: app)
    }

    /// The newest post is a portrait salad, shown taller than wide; a tap opens it full screen,
    /// a pinch zooms in, and swiping down puts it back. 关闭 closes it too.
    func testPhotoViewer() {
        continueAfterFailure = false
        let app = launch(language: "zh-Hans")
        let photos = app.descendants(matching: .any).matching(identifier: "feed.photos").firstMatch
        XCTAssertTrue(photos.waitForExistence(timeout: Self.wait), "no photos in 动态")
        XCTAssertGreaterThan(photos.frame.height, photos.frame.width, "the portrait salad isn't shown portrait")
        settle()
        keepScreenshot(named: "48-feed-portrait")

        photos.tap()
        let viewer = app.descendants(matching: .any).matching(identifier: "photoViewer").firstMatch
        XCTAssertTrue(viewer.waitForExistence(timeout: Self.wait), "tapping the photo didn't open it full screen")
        let close = app.buttons["photoViewer.close"]
        XCTAssertTrue(close.waitForExistence(timeout: Self.wait), "no 关闭")
        assertOnScreen(close, in: app)
        settle()
        keepScreenshot(named: "48-feed-photo-viewer")
        viewer.pinch(withScale: 2.5, velocity: 2)
        settle()
        keepScreenshot(named: "48-feed-photo-viewer-zoomed")
        viewer.doubleTap()
        settle()
        close.tap()
        XCTAssertTrue(viewer.waitForNonExistence(timeout: Self.wait), "关闭 didn't close the photo")

        // Swipe-to-close starts from a freshly opened photo, so a pinch the simulator missed
        // can't leave it zoomed in and turn the swipe into a pan.
        XCTAssertTrue(photos.waitForExistence(timeout: Self.wait), "动态 didn't come back")
        photos.tap()
        XCTAssertTrue(close.waitForExistence(timeout: Self.wait), "the photo didn't open again")
        settle()
        viewer.swipeDown(velocity: .fast)
        XCTAssertTrue(viewer.waitForNonExistence(timeout: Self.wait), "swiping down didn't close the photo")
        XCTAssertTrue(photos.waitForExistence(timeout: Self.wait), "动态 didn't come back")
    }

    /// A 训练 shows its numbers on the 成绩条 under its cover, 时长 first, across the card. The newest posts on top
    /// are a run from Apple Health, a 请假条 and a salad, so the strip is scrolled to, a little at a
    /// time, until one clears the tab bar.
    func testScoreStrip() {
        continueAfterFailure = false
        let app = launch(language: "zh-Hans")
        XCTAssertTrue(app.staticTexts["feed.title"].waitForExistence(timeout: Self.wait), "no 动态")
        let strip = app.descendants(matching: .any).matching(identifier: "post.strip")
            .containing(.any, identifier: "strip.duration").firstMatch
        let tabBarTop = tabButton("tab.feed", in: app).frame.minY
        let feed = app.scrollViews.firstMatch
        var drags = 0
        while drags < Self.maxSwipes, !(strip.exists && strip.frame.maxY <= tabBarTop) {
            let from = feed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -240)))
            drags += 1
        }
        XCTAssertTrue(strip.exists, "no 成绩条 on a 训练")
        settle()
        // Kept before the check, so a failure shows where the list stopped.
        keepScreenshot(named: "44-feed-score-strip")
        assertClearOfTheTabBar(strip, in: app)
        // The strip opens the ticket's stub, across the whole card.
        let card = app.descendants(matching: .any).matching(identifier: "feed.post")
            .containing(.any, identifier: "strip.duration").firstMatch
        XCTAssertEqual(strip.frame.minX, card.frame.minX, accuracy: 1, "the 成绩条 doesn't reach the card's left edge")
        XCTAssertEqual(strip.frame.maxX, card.frame.maxX, accuracy: 1, "the 成绩条 doesn't reach the card's right edge")
    }

    /// A post without a cover shows the shared colour block with its words, its minutes on the
    /// 成绩条 under it: the 请假条 near the top, and two days back the tennis serve.
    func testPostsWithoutPhotos() {
        continueAfterFailure = false
        let app = launch(language: "zh-Hans")
        XCTAssertTrue(app.staticTexts["feed.title"].waitForExistence(timeout: Self.wait), "no 动态")
        let blocks = app.descendants(matching: .any).matching(identifier: "post.block")
        XCTAssertTrue(blocks.firstMatch.waitForExistence(timeout: Self.wait), "a 请假条 has no colour block")
        let serve = blocks.matching(NSPredicate(format: "label CONTAINS '发球终于过网了'")).firstMatch
        let tabBarTop = tabButton("tab.feed", in: app).frame.minY
        let feed = app.scrollViews.firstMatch
        var drags = 0
        while drags < Self.maxSwipes, !(serve.exists && serve.frame.maxY <= tabBarTop) {
            let from = feed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -240)))
            drags += 1
        }
        XCTAssertTrue(serve.exists, "the tennis serve without a photo has no colour block")
        XCTAssertFalse(serve.label.contains("50′"), "the block still has the minutes: \(serve.label)")
        settle()
        keepScreenshot(named: "47-feed-no-photo")
        assertClearOfTheTabBar(serve, in: app)
    }

    /// ＋ opens our own emoji grid, and holding a card then sliding along the bar picks.
    func testGridAndHoldToPick() {
        continueAfterFailure = false
        let app = launch(language: "zh-Hans")
        let react = app.buttons.matching(identifier: "feed.react").firstMatch
        XCTAssertTrue(react.waitForExistence(timeout: Self.wait), "no post to react to")
        settle()
        react.tap()
        let bar = app.buttons["feed.emoji.💪"]
        XCTAssertTrue(bar.waitForExistence(timeout: Self.wait), "the emoji bar didn't open")

        // ＋ opens our own emoji grid in place of the bar.
        app.buttons["feed.emoji.more"].tap()
        let grid = app.descendants(matching: .any).matching(identifier: "feed.emojiGrid").firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: Self.wait), "the emoji grid didn't open")
        assertOnScreen(grid, in: app)
        settle()
        keepScreenshot(named: "41-feed-emoji-grid")
        // 全部, as the grid opens on 最近 once this phone has picked before.
        grid.buttons["全部"].firstMatch.tap()
        grid.buttons["😀"].firstMatch.tap()
        waitFor(react, "label == '我的回应：😀'", "picking from the grid didn't react")

        // Holding the card and sliding to 😂 swaps it: the bar's slots sit left of my button's
        // right edge, 44 points each. A 练了 card's character trains on screen, so the simulator
        // is never idle and touches arrive late: the press holds well past the long press's 0.45s,
        // slides slowly and rests on the slot, so the hold and the slot both register.
        let button = react.frame
        let screen = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        let slot = screen.withOffset(CGVector(dx: button.maxX - (7 - 2.5) * 44 - 4, dy: button.minY - 8 - 26))
        // Pressed on the card's words, above its row.
        let words = screen.withOffset(CGVector(dx: button.minX - 120, dy: button.minY - 50))
        words.press(forDuration: 2, thenDragTo: slot, withVelocity: 150, thenHoldForDuration: 0.5)
        keepScreenshot(named: "41-feed-hold-slide")
        waitFor(react, "label == '我的回应：😂'", "holding and sliding didn't pick 😂")
    }

    /// A card's comments open its own page over the feed, with the tab bar gone: every comment,
    /// tapping a teammate's one replies to them, a sent comment shows at once, and 返回 comes
    /// back to the feed, whose card shows it.
    func testComments() {
        continueAfterFailure = false
        let app = launch(language: "zh-Hans")
        let comments = app.buttons.matching(identifier: "feed.comments").firstMatch
        XCTAssertTrue(comments.waitForExistence(timeout: Self.wait), "no card shows comments")
        settle()
        keepScreenshot(named: "48-feed-card-comments")
        comments.tap()

        let rows = app.descendants(matching: .any).matching(identifier: "post.comment")
        XCTAssertTrue(backButton(in: app).waitForExistence(timeout: Self.wait), "the post's page didn't open")
        waitFor(rows.element(boundBy: 2), "exists == true", "the page doesn't list every comment")
        waitFor(
            app.tabBars.firstMatch, "exists == false OR hittable == false", "the tab bar shows over the post's page")
        settle()
        keepScreenshot(named: "49-post-page")

        rows.firstMatch.tap()
        XCTAssertTrue(app.buttons["post.cancelReply"].waitForExistence(timeout: Self.wait), "tapping didn't reply")
        let box = app.descendants(matching: .any).matching(identifier: "post.field").firstMatch
        box.typeText("加油")
        let send = app.buttons["post.send"]
        assertOnScreen(send, in: app)
        settle()
        keepScreenshot(named: "50-post-replying")
        send.tap()
        waitFor(rows.element(boundBy: 3), "exists == true", "the sent comment didn't show")
        XCTAssertFalse(app.buttons["post.cancelReply"].exists, "still replying after sending")

        // Pulled down, the page stays open and keeps every comment, the one just sent too: a
        // read that dropped what the member sent, or left the page, would fail here.
        app.scrollViews.firstMatch.swipeDown(velocity: .fast)
        waitFor(rows.element(boundBy: 3), "exists == true", "pulling to refresh lost a comment")
        XCTAssertTrue(backButton(in: app).exists, "pulling to refresh left the post's page")

        backButton(in: app).tap()
        XCTAssertTrue(app.buttons["tab.feed"].waitForExistence(timeout: Self.wait), "the tab bar didn't come back")
        waitFor(comments, "label CONTAINS '全部 4 条评论'", "the card doesn't count the new comment")
        settle()
        keepScreenshot(named: "51-feed-after-comment")
    }

    func testFeedInEnglish() {
        continueAfterFailure = false
        let app = launch(language: "en")
        XCTAssertTrue(app.staticTexts["feed.title"].waitForExistence(timeout: Self.wait))
        XCTAssertEqual(app.staticTexts["feed.title"].label, "Feed")
        settle()
        keepScreenshot(named: "46-feed-en")
    }

    /// No posts yet: the squad's scene with me in it, and 去打卡 takes me to 今天.
    func testEmptyFeed() {
        continueAfterFailure = false
        let app = launch(language: "zh-Hans", extra: ["-uitest-empty-feed"])
        let checkIn = app.buttons["feed.checkIn"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: Self.wait), "no empty feed")
        settle()
        assertClearOfTheTabBar(checkIn, in: app)
        keepScreenshot(named: "47-feed-empty")
        checkIn.tap()
        // By its place in the bar when need be: opened straight on 动态, the system's bar may not
        // carry the tabs' identifiers, so `tab.today` alone is never found.
        waitFor(tabButton("tab.today", in: app), "isSelected == true", "去打卡 didn't open 今天")
    }

    /// 动态 opened with no server and nothing read before: 网络开小差了 with 再试一次, not a
    /// blank page.
    func testOfflineFeedSaysSo() {
        let app = launch(language: "zh-Hans", extra: ["-uitest-offline-feed"])
        let retry = app.buttons["feed.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: Self.wait), "no 再试一次 on an offline feed")
        XCTAssertTrue(app.staticTexts["网络开小差了"].exists, "no 网络开小差了 on an offline feed")
        XCTAssertFalse(app.buttons["feed.checkIn"].exists, "the empty scene on a feed that wasn't read")
        settle()
        assertClearOfTheTabBar(retry, in: app)
        keepScreenshot(named: "47-feed-offline")
    }

    private func launch(language: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments +=
            [
                "-AppleLanguages", "(\(language))", "-AppleLocale", language, "-uitest-no-push", "-uitest-noon", "-tab",
                "feed",
            ] + extra
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        return app
    }

    /// Fully on screen and above the floating tab bar, so nothing covers it.
    private func assertClearOfTheTabBar(_ element: XCUIElement, in app: XCUIApplication) {
        assertOnScreen(element, in: app)
        let bar = tabButton("tab.feed", in: app)
        XCTAssertLessThanOrEqual(element.frame.maxY, bar.frame.minY, "\(element.identifier) is under the tab bar")
    }

    /// A tap anywhere but the panel closes it: in the larger gap above or below it, clear of the
    /// tab bar. The panel opens over its row when there is no room under it, which can put it over
    /// the title, so tapping the title isn't always a tap outside.
    private func tapOutside(_ panel: XCUIElement, in app: XCUIApplication) {
        let screen = app.windows.firstMatch.frame
        let top = app.staticTexts["feed.title"].frame.minY
        let bottom = tabButton("tab.feed", in: app).frame.minY
        let above = panel.frame.minY - top
        let below = bottom - panel.frame.maxY
        let y = above > below ? top + above / 2 : panel.frame.maxY + below / 2
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: screen.midX, dy: y))
            .tap()
    }

    private func assertOnScreen(_ element: XCUIElement, in app: XCUIApplication) {
        let screen = app.windows.firstMatch.frame
        XCTAssertTrue(screen.contains(element.frame), "\(element.identifier) is cut off: \(element.frame)")
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

extension FeedUITests {
    /// A 训练 whose cover is only its map or chart (no photo) meets its 成绩条 in a straight line:
    /// the cover's pages are square at the bottom. The run by the river is scrolled to, and its
    /// cover, with the strip under it, is kept for a look at where they meet.
    func testMapCoverMeetsTheScoreStripSquare() {
        continueAfterFailure = false
        let app = launch(language: "zh-Hans")
        XCTAssertTrue(app.staticTexts["feed.title"].waitForExistence(timeout: Self.wait), "no 动态")
        let map = app.descendants(matching: .any).matching(identifier: "feed.map").firstMatch
        let tabBarTop = tabButton("tab.feed", in: app).frame.minY
        let feed = app.scrollViews.firstMatch
        var drags = 0
        while drags < Self.maxSwipes, !(map.exists && map.frame.maxY + Self.stripHeight <= tabBarTop) {
            let from = feed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -240)))
            drags += 1
        }
        XCTAssertTrue(map.exists, "no map-only cover")
        settle()
        keepScreenshot(named: "44-feed-map-cover-strip")
    }
}

extension FeedUITests {
    /// A rated meal shows its 健康 and 好吃 in stars and the 卡价比 worked out from them on its
    /// 成绩条, as a 训练 shows its numbers: Mia's salad today, rated 5 and 4. A tap on 卡价比 says
    /// what it is.
    func testMealScoreStrip() {
        continueAfterFailure = false
        let app = launch(language: "zh-Hans")
        XCTAssertTrue(app.staticTexts["feed.title"].waitForExistence(timeout: Self.wait), "no 动态")
        let strip = app.descendants(matching: .any).matching(identifier: "post.strip")
            .containing(.any, identifier: "strip.healthy").firstMatch
        let tabBarTop = tabButton("tab.feed", in: app).frame.minY
        let feed = app.scrollViews.firstMatch
        var drags = 0
        while drags < Self.maxSwipes, !(strip.exists && strip.frame.maxY <= tabBarTop) {
            let from = feed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -240)))
            drags += 1
        }
        XCTAssertTrue(strip.exists, "no 成绩条 on the rated salad")
        settle()
        keepScreenshot(named: "45-feed-meal-strip")
        assertClearOfTheTabBar(strip, in: app)
        for (cell, words) in [("strip.healthy", "5健康"), ("strip.tasty", "4好吃"), ("strip.calorieValue", "4.0卡价比")] {
            let label = strip.descendants(matching: .any).matching(identifier: cell).firstMatch.label
            // VoiceOver joins a cell's parts with the language's list separator (「、」 in Chinese).
            let joined = label.filter { !" ,、".contains($0) }
            XCTAssertEqual(joined, words, "\(cell) reads \(label)")
        }
        // 卡价比 says what it is on a tap, over the card, which stays.
        strip.descendants(matching: .any).matching(identifier: "strip.calorieValue").firstMatch.tap()
        let tip = app.staticTexts["卡路里性价比"]
        XCTAssertTrue(tip.waitForExistence(timeout: Self.wait), "no 卡价比 tip")
        keepScreenshot(named: "45b-feed-meal-strip-tip")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        XCTAssertTrue(tip.waitForNonExistence(timeout: Self.wait), "the 卡价比 tip stayed")
        XCTAssertTrue(strip.exists, "the strip went")
        XCTAssertFalse(app.descendants(matching: .any)["post.comment"].exists, "the tap opened the post")
    }
}
