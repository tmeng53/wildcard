import XCTest

extension XCTestCase {
    /// Taps and typing update the UI on the next frames, so wait for the state instead of checking
    /// at once. A busy CI simulator can take seconds per accessibility query; a wait that succeeds
    /// returns as soon as it does.
    func waitFor(_ element: XCUIElement, _ predicate: String, _ message: String, timeout: TimeInterval = 30) {
        let met = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [met], timeout: timeout), .completed, message)
    }

    /// Waits until `element` is laid out on screen, then for it to be hittable. While a page is
    /// still moving in, an element can exist with no frame yet, and asking it `isHittable` then
    /// fails the test at once ("Failed to determine hittability") instead of waiting.
    @MainActor
    func waitForHittable(_ element: XCUIElement, _ message: String, timeout: TimeInterval = 30) {
        let deadline = Date.now.addingTimeInterval(timeout)
        while !Self.isLaidOut(element), Date.now < deadline {
            RunLoop.current.run(until: Date.now.addingTimeInterval(0.5))
        }
        XCTAssertTrue(Self.isLaidOut(element), message)
        waitFor(element, "isHittable == true", message, timeout: timeout)
    }

    @MainActor
    private static func isLaidOut(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        return frame.minX.isFinite && frame.minY.isFinite && !frame.isEmpty
    }

    /// Swipes the coach page's top card right, into 以前. The swipe is drawn on the screen where
    /// the top card's stage is rather than on the card's element: asking a busy CI simulator for
    /// the card's snapshot the moment before can come back empty while the card is right there,
    /// failing the swipe (main, 2026-11-14).
    @MainActor
    func swipeTopCoachCard(in app: XCUIApplication) {
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.35))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.35))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
    }

    /// Taps `element` until `target` meets `predicate`: a busy CI simulator now and then drops a
    /// tap that lands as a page finishes moving (the app did nothing, and the same tap works on the
    /// test's retry), so it taps once more if nothing came of the first within 10 s. Only for taps
    /// whose second press can't undo the first one's effect once that effect has shown.
    func tap(
        _ element: XCUIElement, until target: XCUIElement, _ predicate: String, _ message: String,
        timeout: TimeInterval = 30
    ) {
        element.tap()
        let met = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: target)
        if XCTWaiter().wait(for: [met], timeout: 10) == .completed { return }
        element.tap()
        waitFor(target, predicate, message, timeout: timeout)
    }

    /// A tab's button in the system tab bar (`tab.today`, `tab.feed`, `tab.me`), waited for. The
    /// system's bar doesn't always carry the tabs' identifiers (it can show before they arrive,
    /// and drops them at times while a page is pushed), so it falls back to the tab's place in it.
    func tabButton(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons[identifier]
        if button.waitForExistence(timeout: 5) { return button }
        let place = ["tab.today", "tab.feed", "tab.me"].firstIndex(of: identifier) ?? 0
        let inBar = app.tabBars.firstMatch.buttons.element(boundBy: place)
        XCTAssertTrue(inBar.waitForExistence(timeout: 30), "no \(identifier) in the tab bar")
        return inBar
    }

    /// The system's back button on a pushed page, in its navigation bar: pages open over another
    /// on the tab's NavigationStack, so none draws a back button of its own.
    func backButton(in app: XCUIApplication) -> XCUIElement {
        app.navigationBars.buttons.element(boundBy: 0)
    }
}
