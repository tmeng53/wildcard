import XCTest

/// 收藏 on the sample squad (Tracy, 2026-11-12): a place's bookmark pops up the note card with
/// the keyboard up, 收藏 fills the bookmark, 我's bookmark lists the place with its note, a row
/// opens its page, and a swipe left removes it. Screenshots are kept for review against the
/// approved design (收藏 ①, ②, ③, ④).
@MainActor
final class SavedPlacesUITests: XCTestCase {
    private static let wait: TimeInterval = 30

    func testAPlaceIsSavedWithANoteListedOnMeAndRemoved() {
        continueAfterFailure = false
        let app = launch()
        openAPlace(in: app)

        // ① The bookmark at the bar's right; ② its card, with the keyboard up.
        let bookmark = app.buttons["place.save"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: Self.wait), "the place's page has no bookmark")
        XCTAssertEqual(bookmark.label, "收藏")
        settle()
        keepScreenshot(named: "saved-places-1-bookmark")
        bookmark.tap()
        let note = app.textFields["savePlace.note"]
        XCTAssertTrue(note.waitForExistence(timeout: Self.wait), "the bookmark didn't pop up the note card")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: Self.wait), "the keyboard didn't come up")
        note.typeText("周六早上的单车课")
        let save = app.buttons["savePlace.save"]
        assertClearOfTheKeyboard(save, in: app)
        assertClearOfTheKeyboard(app.buttons["savePlace.cancel"], in: app)
        XCTAssertFalse(app.buttons["savePlace.remove"].exists, "a place not saved yet offers 取消收藏")
        settle()
        keepScreenshot(named: "saved-places-2-card")
        save.tap()
        XCTAssertTrue(note.waitForNonExistence(timeout: Self.wait), "收藏 didn't close the card")
        waitFor(bookmark, "label == '已收藏'", "the bookmark didn't fill")

        checkTheSavedPlacesCard(in: app, bookmark: bookmark, note: note)
        checkTheListOnMe(in: app)
    }

    /// The same card again changes the note and offers 取消收藏.
    private func checkTheSavedPlacesCard(in app: XCUIApplication, bookmark: XCUIElement, note: XCUIElement) {
        bookmark.tap()
        XCTAssertTrue(app.buttons["savePlace.remove"].waitForExistence(timeout: Self.wait), "no 取消收藏 on a saved place")
        XCTAssertEqual(note.value as? String, "周六早上的单车课", "the card lost the note")
        assertClearOfTheKeyboard(app.buttons["savePlace.remove"], in: app)
        settle()
        keepScreenshot(named: "saved-places-2b-card-saved")
        app.buttons["savePlace.cancel"].tap()
        XCTAssertTrue(note.waitForNonExistence(timeout: Self.wait), "取消 didn't close the card")

    }

    /// ④ 我's bookmark; ③ the list, a row opening its place, a swipe left removing it.
    private func checkTheListOnMe(in app: XCUIApplication) {
        tabButton("tab.me", in: app).tap()
        let open = app.buttons["me.savedPlaces"]
        XCTAssertTrue(open.waitForExistence(timeout: Self.wait), "我 has no 收藏 button")
        assertOnScreen(open, in: app)
        settle()
        keepScreenshot(named: "saved-places-4-me")
        open.tap()
        let row = app.buttons["savedPlaces.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.wait), "收藏 lists nothing")
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS '周六早上的单车课'")).firstMatch.exists
                || row.label.contains("周六早上的单车课"), "the row doesn't show the note")
        assertOnScreen(row, in: app)
        settle()
        keepScreenshot(named: "saved-places-3-list")

        // A row opens the place's page, saved.
        row.tap()
        XCTAssertTrue(
            app.staticTexts["place.name"].waitForExistence(timeout: Self.wait), "the row didn't open the place")
        waitFor(app.buttons["place.save"], "label == '已收藏'", "the place opened from 收藏 isn't saved")
        backButton(in: app).tap()

        // A swipe left removes it.
        XCTAssertTrue(row.waitForExistence(timeout: Self.wait), "back didn't return to 收藏")
        row.swipeLeft()
        let delete = app.buttons["删除"]
        if delete.waitForExistence(timeout: 3) { delete.tap() }
        XCTAssertTrue(
            app.staticTexts["还没有收藏"].waitForExistence(timeout: Self.wait), "the swiped place is still listed")
        settle()
        keepScreenshot(named: "saved-places-3b-empty")
    }

    /// 动态's map, 常去, its first place.
    private func openAPlace(in app: XCUIApplication) {
        let map = app.buttons["squadMap.open"]
        XCTAssertTrue(map.waitForExistence(timeout: Self.wait), "no map button on 动态")
        map.tap()
        app.segmentedControls.buttons.element(boundBy: 1).tap()
        let place = app.buttons["squadMap.oftenRow"].firstMatch
        XCTAssertTrue(place.waitForExistence(timeout: Self.wait), "常去 lists no place")
        place.tap()
        XCTAssertTrue(app.staticTexts["place.name"].waitForExistence(timeout: Self.wait), "the place didn't open")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon", "-tab",
            "feed",
        ]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        return app
    }

    private func assertOnScreen(_ element: XCUIElement, in app: XCUIApplication) {
        let screen = app.windows.firstMatch.frame
        XCTAssertTrue(screen.contains(element.frame), "\(element.identifier) is cut off: \(element.frame)")
    }

    /// On screen and above the keyboard, so it can be tapped while typing.
    private func assertClearOfTheKeyboard(_ element: XCUIElement, in app: XCUIApplication) {
        assertOnScreen(element, in: app)
        let keyboard = app.keyboards.firstMatch.frame
        XCTAssertLessThanOrEqual(element.frame.maxY, keyboard.minY, "\(element.identifier) is under the keyboard")
    }

    private func settle() {
        Thread.sleep(forTimeInterval: 1.5)
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
