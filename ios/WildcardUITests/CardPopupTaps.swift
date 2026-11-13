import XCTest

extension XCTestCase {
    /// Taps the dim just above `top`, the highest thing a card pop-up shows (a teammate's today, or
    /// the card itself), which closes it. The card grows to the page, so a fixed spot on the
    /// screen can land on it; just above what it shows is always off it.
    func tapOffPopup(above top: XCUIElement, in app: XCUIApplication) {
        let frame = top.frame
        XCTAssertGreaterThan(frame.minY, Self.offPopup * 2, "no room above the pop-up to tap off it: \(frame)")
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.minY - Self.offPopup))
            .tap()
    }

    private static var offPopup: Double { 12 }
}
