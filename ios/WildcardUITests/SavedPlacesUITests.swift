import XCTest

/// 收藏 on the sample squad (Tracy, 2026-11-14, v2 A): a place's bookmark saves it at once and
/// fills, a 写备注 row under the name turns into the field in place, the filled bookmark asks before
/// taking a place with a note off, 我's bookmark lists the place, a row opens its page, and a swipe
/// left removes it. Screenshots are kept for review against the approved design.
@MainActor
final class SavedPlacesUITests: XCTestCase {
    private static let wait: TimeInterval = 30
    private static let note = "周六早上的单车课"

    func testAPlaceIsSavedWithANoteListedOnMeAndRemoved() {
        continueAfterFailure = false
        let app = launch()
        openAPlace(in: app)

        let bookmark = app.buttons["place.save"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: Self.wait), "the place's page has no bookmark")
        waitFor(bookmark, "label == '收藏' AND isEnabled == true", "the bookmark isn't ready")
        XCTAssertFalse(app.buttons["place.note"].exists, "a place not saved yet shows a note row")
        settle()
        keepScreenshot(named: "154a-saved-places-bookmark")

        // One tap saves it: no card, the bookmark fills and 写备注 shows under the name.
        bookmark.tap()
        waitFor(bookmark, "label == '已收藏'", "the bookmark didn't fill")
        let noteRow = app.buttons["place.note"]
        XCTAssertTrue(noteRow.waitForExistence(timeout: Self.wait), "no 写备注 under a saved place")
        XCTAssertTrue(noteRow.label.contains("写备注"), "the note row says \(noteRow.label)")
        settle()
        keepScreenshot(named: "154b-saved-places-saved")

        writeTheNote(in: app, row: noteRow)
        takeItOffWithTheNote(in: app, bookmark: bookmark)
        checkTheListOnMe(in: app)
    }

    /// 写备注 turns into the field with the keyboard up; the keyboard's ✓ saves it.
    private func writeTheNote(in app: XCUIApplication, row: XCUIElement) {
        row.tap()
        let field = app.textFields["place.noteField"]
        XCTAssertTrue(field.waitForExistence(timeout: Self.wait), "写备注 didn't open the field")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: Self.wait), "the keyboard didn't come up")
        field.typeText(Self.note)
        assertClearOfTheKeyboard(field, in: app)
        settle()
        keepScreenshot(named: "154c-saved-places-writing")
        field.typeText("\n")
        XCTAssertTrue(field.waitForNonExistence(timeout: Self.wait), "✓ didn't save the note")
        waitFor(row, "label CONTAINS '\(Self.note)'", "the note isn't under the name")
        settle()
        keepScreenshot(named: "154d-saved-places-note")
    }

    /// The filled bookmark asks first when the place has a note, then takes it off; one more tap saves
    /// it again, without a note, for the list.
    private func takeItOffWithTheNote(in app: XCUIApplication, bookmark: XCUIElement) {
        bookmark.tap()
        let remove = app.buttons["取消收藏"]
        XCTAssertTrue(remove.waitForExistence(timeout: Self.wait), "no confirmation before losing the note")
        settle()
        keepScreenshot(named: "154e-saved-places-confirm")
        remove.tap()
        waitFor(bookmark, "label == '收藏'", "取消收藏 left it saved")
        XCTAssertTrue(app.buttons["place.note"].waitForNonExistence(timeout: Self.wait), "the note row stayed")
        bookmark.tap()
        waitFor(bookmark, "label == '已收藏'", "the bookmark didn't fill again")
    }

    /// 我's bookmark; the list, a row opening its place, a swipe left removing it.
    private func checkTheListOnMe(in app: XCUIApplication) {
        // 地点页 sits on 小队地图, which hides the tab bar: back out to 动态 first.
        for _ in 0..<3 where !app.tabBars.firstMatch.waitForExistence(timeout: 3) {
            backButton(in: app).tap()
        }
        tabButton("tab.me", in: app).tap()
        let open = app.buttons["me.savedPlaces"]
        XCTAssertTrue(open.waitForExistence(timeout: Self.wait), "我 has no 收藏 button")
        assertOnScreen(open, in: app)
        open.tap()
        let row = app.buttons["savedPlaces.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.wait), "收藏 lists nothing")
        XCTAssertTrue(row.label.contains("写备注"), "a place without a note doesn't offer 写备注: \(row.label)")
        assertOnScreen(row, in: app)
        settle()
        keepScreenshot(named: "154f-saved-places-list")

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
        keepScreenshot(named: "154g-saved-places-empty")
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
