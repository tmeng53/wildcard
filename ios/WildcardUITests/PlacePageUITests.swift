import XCTest

/// A tagged place's page (地点页): a post's place opens it over 动态 instead of Apple Maps. Mia's
/// salad came from Sweetgreen, a restaurant: its page shows the meals' 健康, 好吃 and 卡价比. My leg
/// day was at Equinox Flatiron, a gym 阿杰 and Coco scored 5 and 4: its page shows the squad's
/// 4.5, and my own score changes it. A post on the page opens that post.
@MainActor
final class PlacePageUITests: XCTestCase {
    private static let wait: TimeInterval = 30
    /// More than the sample squad's posts need to reach yesterday's leg day.
    private static let maxDrags = 30

    func testARestaurantsPageShowsItsMeals() {
        let app = launch()
        let tag = placeTag("Sweetgreen", in: app)
        tag.tap()
        let title = app.staticTexts["place.title"]
        XCTAssertTrue(title.waitForExistence(timeout: Self.wait), "the place's page didn't open")
        XCTAssertEqual(title.label, "Sweetgreen")
        let numbers = app.descendants(matching: .any)["place.numbers"]
        XCTAssertTrue(numbers.waitForExistence(timeout: Self.wait), "no numbers on the page")
        XCTAssertTrue(
            numbers.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '卡价比'")).firstMatch
                .exists, "a restaurant's numbers don't show 卡价比")
        XCTAssertFalse(app.descendants(matching: .any)["place.myStars"].exists, "a restaurant asks for my score")
        settle()
        keepScreenshot(named: "148-place-page-restaurant")
        assertOnScreen(numbers, in: app)
    }

    func testAGymsPageTakesMyScoreAndOpensItsPosts() {
        let app = launch()
        let tag = placeTag("Equinox Flatiron", in: app)
        tag.tap()
        let numbers = app.descendants(matching: .any)["place.numbers"]
        XCTAssertTrue(numbers.waitForExistence(timeout: Self.wait), "the gym's page didn't open")
        XCTAssertTrue(
            squadScore("4.5", in: numbers).waitForExistence(timeout: Self.wait), "the squad's score isn't 4.5")
        settle()
        keepScreenshot(named: "149-place-page-gym")
        assertOnScreen(numbers, in: app)

        // The fourth of five stars: (5 + 4 + 4) / 3 is 4.3.
        let stars = app.descendants(matching: .any)["place.myStars"]
        XCTAssertTrue(stars.exists, "a gym doesn't ask for my score")
        stars.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).tap()
        XCTAssertTrue(squadScore("4.3", in: numbers).waitForExistence(timeout: Self.wait), "my score didn't count")
        settle()
        keepScreenshot(named: "150-place-page-gym-rated")

        let post = app.buttons["place.post"].firstMatch
        XCTAssertTrue(post.exists, "no posts on the gym's page")
        post.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["post.composer"].waitForExistence(timeout: Self.wait),
            "a post on the place's page didn't open")
    }

    private func squadScore(_ score: String, in numbers: XCUIElement) -> XCUIElement {
        numbers.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", score)).firstMatch
    }

    /// Scrolls 动态 until the tag naming `name` is clear of the tab bar.
    private func placeTag(_ name: String, in app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(app.staticTexts["feed.title"].waitForExistence(timeout: Self.wait), "no 动态")
        let tag = app.buttons.matching(NSPredicate(format: "identifier == 'post.place' AND label == %@", name))
            .firstMatch
        let tabBarTop = tabButton("tab.feed", in: app).frame.minY
        let feed = app.scrollViews.firstMatch
        var drags = 0
        while drags < Self.maxDrags, !(tag.exists && tag.isHittable && tag.frame.maxY <= tabBarTop) {
            let from = feed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -240)))
            drags += 1
        }
        XCTAssertTrue(tag.exists, "no \(name) tag on 动态")
        return tag
    }

    private func assertOnScreen(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(app.windows.firstMatch.frame.contains(element.frame), "\(element.identifier) is cut off")
    }

    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon", "-tab",
            "feed",
        ]
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
