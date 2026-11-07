import XCTest

/// Home's squad card folded into its glass capsule (the approved 收起, 2026-11-06), on the sample
/// squad at noon, with screenshots for review.
@MainActor
final class TodayCapsuleUITests: XCTestCase {
    /// Slow CI simulators can take many seconds to show a screen; a real failure still fails.
    private static let wait: TimeInterval = 30

    /// Home opens on the capsule (eight members: three heads and 「+5」, then my week), which sits
    /// on the screen with every day inside it; a tap opens the card and its grabber folds it again.
    func testCardFoldsIntoItsCapsule() {
        let app = launch(language: "zh-Hans")
        let capsule = expectCapsule(in: app)
        XCTAssertFalse(app.buttons["squadcard.squad"].exists, "the folded card still shows its squad page")
        settle()
        keepScreenshot(named: "12-today-capsule")

        capsule.tap()
        let squadName = app.descendants(matching: .any)["squadcard.squad"]
        XCTAssertTrue(squadName.waitForExistence(timeout: Self.wait), "a tap didn't open the card")
        settle()
        keepScreenshot(named: "12b-today-card-open")

        let fold = app.buttons["squadcard.collapse"]
        XCTAssertTrue(fold.exists, "the open card has no grabber")
        fold.tap()
        XCTAssertTrue(capsule.waitForExistence(timeout: Self.wait), "the grabber didn't fold the card")
        XCTAssertTrue(squadName.waitForNonExistence(timeout: Self.wait), "the card stayed open")
    }

    /// A swipe down on the capsule opens the card, and a swipe up on the card folds it.
    func testSwipesOpenAndFoldTheCard() {
        let app = launch(language: "zh-Hans")
        let capsule = expectCapsule(in: app)
        capsule.swipeDown()
        let squadName = app.descendants(matching: .any)["squadcard.squad"]
        XCTAssertTrue(squadName.waitForExistence(timeout: Self.wait), "a swipe down didn't open the card")
        app.descendants(matching: .any).matching(identifier: "today.card").firstMatch.swipeUp()
        XCTAssertTrue(capsule.waitForExistence(timeout: Self.wait), "a swipe up didn't fold the card")
    }

    /// The card opens again on the page it was folded on, showing that page and not only its dot.
    func testCardReopensOnItsPage() {
        let app = launch(language: "zh-Hans")
        let capsule = expectCapsule(in: app)
        capsule.swipeDown()
        let mineDot = app.buttons["squadcard.page.mine"]
        XCTAssertTrue(mineDot.waitForExistence(timeout: Self.wait), "a swipe down didn't open the card")
        mineDot.tap()
        XCTAssertTrue(app.buttons["squadcard.collapse"].exists, "tapping my week's dot folded the card")
        let card = app.descendants(matching: .any).matching(identifier: "today.card").firstMatch
        let monday = app.buttons["squadcard.day.0"]
        expect(monday, showsIn: card, "my week didn't show after its dot was tapped")

        card.swipeUp()
        XCTAssertTrue(capsule.waitForExistence(timeout: Self.wait), "a swipe up didn't fold the card")
        capsule.swipeDown()
        XCTAssertTrue(mineDot.waitForExistence(timeout: Self.wait), "a swipe down didn't open the card again")
        XCTAssertTrue(mineDot.isSelected, "the card didn't reopen on my week's dot")
        expect(monday, showsIn: card, "the card reopened on my week's dot but showed the squad's page")
        XCTAssertFalse(
            card.frame.contains(app.buttons["squadcard.squad"].frame), "the squad's page shows under my week's dot")
    }

    /// Once the card has come to rest, `element` sits inside it.
    private func expect(_ element: XCUIElement, showsIn card: XCUIElement, _ message: String) {
        settle()
        XCTAssertTrue(card.frame.contains(element.frame), "\(message): \(element.frame) in \(card.frame)")
    }

    /// In English, with one member, the capsule still fits.
    func testCapsuleInEnglishAlone() {
        let app = launch(language: "en", extra: ["-uitest-squad", "1"])
        _ = expectCapsule(in: app)
        settle()
        keepScreenshot(named: "12c-today-capsule-en-alone")
    }

    /// The capsule inside the window and clear of 打卡.
    private func expectCapsule(in app: XCUIApplication) -> XCUIElement {
        let capsule = app.buttons["squadcard.capsule"]
        XCTAssertTrue(capsule.waitForExistence(timeout: Self.wait), "home didn't open on the folded capsule")
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(capsule.frame), "the capsule runs off the screen: \(capsule.frame)")
        XCTAssertLessThan(capsule.frame.maxY, app.buttons["today.checkin"].frame.minY, "the capsule runs under 打卡")
        return capsule
    }

    private func launch(language: String, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments +=
            [
                "-AppleLanguages", "(\(language))", "-AppleLocale", language, "-uitest-no-push", "-uitest-noon",
                "-uitest-card-folded",
            ] + extra
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        return app
    }

    /// Lets springs and blurs settle before a screenshot.
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
