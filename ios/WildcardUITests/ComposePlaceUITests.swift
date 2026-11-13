import XCTest

/// Tagging a place: 添加位置 on the compose ticket, the map sheet it opens, the place's tag under
/// its author on 动态 and the place's page it opens. The sample squad has no location, so the
/// sheet only searches.
@MainActor
final class ComposePlaceUITests: XCTestCase {
    private static let wait: TimeInterval = 30
    /// More than the sample squad's posts need to reach Mia's salad.
    private static let maxDrags = 24

    /// 添加位置 sits on the caption's row, left of the count, and opens the map with its search
    /// field and 添加, off until a place is selected; 取消 closes it with nothing picked.
    func testAddLocationOpensTheMap() {
        let app = launch(extra: ["-today.cardPage", "0"])
        let checkIn = app.buttons["today.checkin"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: Self.wait), "no 打卡 button")
        checkIn.tap()
        let trained = app.buttons["today.capsule.trained"]
        XCTAssertTrue(trained.waitForExistence(timeout: Self.wait), "no 训练 capsule")
        trained.tap()

        let pill = app.buttons["compose.place"]
        let count = app.staticTexts["compose.count"]
        XCTAssertTrue(pill.waitForExistence(timeout: Self.wait), "no 添加位置 on the compose page")
        XCTAssertLessThan(pill.frame.maxX, count.frame.minX, "添加位置 isn't left of the count")
        XCTAssertEqual(pill.frame.midY, count.frame.midY, accuracy: 12, "添加位置 isn't on the count's row")
        settle()
        keepScreenshot(named: "15-compose-place-pill")

        pill.tap()
        let search = app.descendants(matching: .any).matching(identifier: "place.search").firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: Self.wait), "the map sheet didn't open")
        settle()
        keepScreenshot(named: "15-compose-place-sheet")
        XCTAssertTrue(app.windows.firstMatch.frame.contains(search.frame), "the search field is cut off")
        // A tap on a row or pin only selects it; 添加 picks, and waits for a selection.
        let add = app.buttons["place.add"]
        XCTAssertTrue(add.exists, "no 添加 on the map sheet")
        XCTAssertFalse(add.isEnabled, "添加 is on with nothing selected")

        app.buttons["place.cancel"].tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: Self.wait), "取消 didn't close the map")
        XCTAssertTrue(pill.exists, "取消 left a place on the post")
    }

    /// Mia's salad was tagged at a restaurant: 动态 shows the place's name under her, clear of
    /// the tab bar.
    func testATaggedPlaceShowsOnTheFeed() {
        let app = launch(extra: ["-tab", "feed"])
        let tag = scrollToTag(in: app)
        settle()
        keepScreenshot(named: "44-feed-place-tag")
        XCTAssertEqual(tag.label, "Sweetgreen", "the tag doesn't name the place")
        XCTAssertLessThanOrEqual(
            tag.frame.maxY, tabButton("tab.feed", in: app).frame.minY, "the place tag is under the tab bar")
    }

    /// A tap on the tag pushes the place's own page, not Apple Maps: its card names the place,
    /// shows the squad's numbers and the salad as a tile, all on screen.
    func testAPlaceTagOpensThePlacesPage() {
        let app = launch(extra: ["-tab", "feed"])
        scrollToTag(in: app).tap()
        let name = app.staticTexts["place.name"]
        XCTAssertTrue(name.waitForExistence(timeout: Self.wait), "the tag didn't open the place's page")
        XCTAssertEqual(name.label, "Sweetgreen", "the page doesn't name the place")
        let stats = app.descendants(matching: .any).matching(identifier: "place.stats").firstMatch
        XCTAssertTrue(stats.exists, "no squad numbers on the card")
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(name.frame), "the place's name is cut off")
        XCTAssertTrue(window.contains(stats.frame), "the squad's numbers are cut off")
        XCTAssertTrue(app.buttons["place.openInMaps"].exists, "no 在地图中打开")
        settle()
        keepScreenshot(named: "45-place-page")
        let tile = app.buttons["place.post"].firstMatch
        let page = app.scrollViews.firstMatch
        var drags = 0
        while drags < 4, !(tile.exists && tile.isHittable) {
            let from = page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -240)))
            drags += 1
        }
        XCTAssertTrue(tile.exists, "the salad isn't a tile on the place's page")
        settle()
        keepScreenshot(named: "45-place-page-posts")
    }

    /// Scrolls 动态 down to Mia's salad's place tag, clear of the tab bar.
    @discardableResult private func scrollToTag(in app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(app.staticTexts["feed.title"].waitForExistence(timeout: Self.wait), "no 动态")
        let tag = app.buttons.matching(identifier: "post.place").firstMatch
        let tabBarTop = tabButton("tab.feed", in: app).frame.minY
        let feed = app.scrollViews.firstMatch
        var drags = 0
        while drags < Self.maxDrags, !(tag.exists && tag.isHittable && tag.frame.maxY <= tabBarTop) {
            let from = feed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -240)))
            drags += 1
        }
        XCTAssertTrue(tag.exists, "no place tag on the tagged salad")
        return tag
    }

    private func launch(extra: [String]) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments +=
            ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon"] + extra
        // Home opens on the folded capsule, as these tests were written for.
        app.launchArguments.append("-uitest-card-folded")
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
}
