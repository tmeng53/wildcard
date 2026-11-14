import XCTest

extension FeedUITests {
    /// Under the byline, when the sample run happened (it ended at 7:00), apart from when it was
    /// posted, scrolled to until it clears the tab bar.
    func seeWhenItWasDone(on card: XCUIElement, in feed: XCUIElement, above tabBarTop: CGFloat) {
        let time = card.descendants(matching: .any).matching(identifier: "post.workoutTime").firstMatch
        var drags = 0
        while drags < Self.maxSwipes, !(time.exists && time.frame.maxY <= tabBarTop) {
            let from = feed.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -120)))
            drags += 1
        }
        XCTAssertTrue(time.exists, "a 训练 from Apple Health doesn't say when it was done")
        settle()
        keepScreenshot(named: "44-feed-workout-time")
        XCTAssertTrue(time.label.contains("7:00"), "the workout's span isn't its own: \(time.label)")
        XCTAssertTrue(card.frame.contains(time.frame), "the workout's time spills out of its card: \(time.frame)")
    }
}
