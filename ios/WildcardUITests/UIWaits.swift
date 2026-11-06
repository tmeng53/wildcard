import XCTest

extension XCTestCase {
    /// Taps and typing update the UI on the next frames, so wait for the state instead of checking
    /// at once. A busy CI simulator can take seconds per accessibility query; a wait that succeeds
    /// returns as soon as it does.
    func waitFor(_ element: XCUIElement, _ predicate: String, _ message: String, timeout: TimeInterval = 30) {
        let met = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [met], timeout: timeout), .completed, message)
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
