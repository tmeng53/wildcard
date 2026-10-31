import XCTest

extension XCTestCase {
    /// Taps and typing update the UI on the next frames, so wait for the state instead of checking
    /// at once. A busy CI simulator can take seconds per accessibility query; a wait that succeeds
    /// returns as soon as it does.
    func waitFor(_ element: XCUIElement, _ predicate: String, _ message: String, timeout: TimeInterval = 30) {
        let met = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [met], timeout: timeout), .completed, message)
    }

    /// A tab's button in the system tab bar (`tab.today`, `tab.feed`, …), waited for: the bar can
    /// show a moment before its buttons carry their identifiers.
    func tabButton(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 30), "no \(identifier) in the tab bar")
        return button
    }
}
