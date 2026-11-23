import XCTest

/// 打卡's ＋ at the tab bar's end and the check-in kinds it opens into (Tracy, 2026-11-21).
@MainActor
final class CheckInMenuUITests: XCTestCase {
    private static let wait: TimeInterval = 15
    private static let kinds = ["trained", "healthyMeal", "cheatMeal"]

    /// The kinds stand in one stack above the ＋, on screen, never touching each other or the
    /// bar, the narrowest on top and the widest next to the ＋: in Simplified Chinese at the
    /// default text size, and in the two languages with the longest words at a large one. Each
    /// launch costs a CI simulator about ten seconds, so the cases that can't overlap when these
    /// don't are left out.
    func testKindsStackByWidthAboveThePlus() {
        let cases = [
            ("zh-Hans", "UICTContentSizeCategoryL"), ("zh-Hant", "UICTContentSizeCategoryAccessibilityXL"),
            ("en", "UICTContentSizeCategoryAccessibilityXL"),
        ]
        for (language, size) in cases {
            let app = launch(language: language, size: size)
            let plus = app.buttons["today.checkin"]
            XCTAssertTrue(plus.waitForExistence(timeout: Self.wait), "no ＋")
            plus.tap()
            _ = app.buttons["today.capsule.cheatMeal"].waitForExistence(timeout: Self.wait)
            settle()
            if language == "zh-Hans" { keepScreenshot(named: "14b-checkin-menu") }
            let frames = Self.kinds.map { kind -> CGRect in
                let capsule = app.buttons["today.capsule.\(kind)"]
                XCTAssertTrue(capsule.waitForExistence(timeout: Self.wait), "no \(kind) capsule")
                return capsule.frame
            }
            let screen = app.windows.firstMatch.frame
            let bar = app.buttons["tab.today"].frame
            let tag = "\(language) \(size)"
            for (first, one) in frames.enumerated() {
                XCTAssertTrue(screen.contains(one), "\(tag): capsule \(first) leaves the screen")
                XCTAssertLessThan(one.maxY, plus.frame.minY, "\(tag): capsule \(first) runs into the ＋")
                XCTAssertLessThan(one.maxY, bar.minY, "\(tag): capsule \(first) runs into the bar")
                for (second, other) in frames.enumerated() where second > first {
                    XCTAssertFalse(one.intersects(other), "\(tag): capsules \(first) and \(second) overlap")
                }
            }
            // Top to bottom, each at least as wide as the one above it, right edges in line.
            let stack = frames.sorted { $0.minY < $1.minY }
            for (upper, lower) in zip(stack, stack.dropFirst()) {
                XCTAssertLessThanOrEqual(upper.width, lower.width + 1, "\(tag): a wider capsule sits higher")
                XCTAssertEqual(upper.maxX, lower.maxX, accuracy: 1, "\(tag): the stack's right edge isn't straight")
            }
            app.terminate()
        }
    }

    /// The ＋ is on every tab: from 动态 the kinds open over it with the bar still up, the ＋ (now a
    /// cross) puts them away, and a pick goes to 小队 and its compose page, which the bar leaves.
    func testCheckInFromAnotherTab() {
        let app = launch(language: "zh-Hans", size: "UICTContentSizeCategoryL")
        let plus = app.buttons["today.checkin"]
        XCTAssertTrue(plus.waitForExistence(timeout: Self.wait), "no ＋")
        app.buttons["tab.feed"].tap()
        XCTAssertTrue(app.staticTexts["feed.title"].waitForExistence(timeout: Self.wait), "动态 didn't open")
        XCTAssertTrue(plus.isHittable, "no ＋ on 动态")

        plus.tap()
        let meal = app.buttons["today.capsule.healthyMeal"]
        XCTAssertTrue(meal.waitForExistence(timeout: Self.wait), "the kinds didn't open on 动态")
        XCTAssertTrue(app.buttons["tab.feed"].isSelected, "the ＋ left 动态")
        XCTAssertTrue(app.buttons["tab.feed"].isHittable, "the bar stepped aside for the kinds")
        XCTAssertEqual(plus.label, "收起", "the cross isn't 收起")
        settle()
        keepScreenshot(named: "14c-checkin-menu-on-feed")
        plus.tap()
        waitFor(meal, "exists == false", "the cross didn't put the kinds away")

        // A tab tapped in the bar puts them away too, the open one included.
        plus.tap()
        XCTAssertTrue(meal.waitForExistence(timeout: Self.wait), "the kinds didn't open again")
        app.buttons["tab.feed"].tap()
        waitFor(meal, "exists == false", "tapping the open tab didn't put the kinds away")

        plus.tap()
        XCTAssertTrue(meal.waitForExistence(timeout: Self.wait), "the kinds didn't open a third time")
        meal.tap()
        XCTAssertTrue(app.buttons["compose.post"].waitForExistence(timeout: Self.wait), "the compose page never opened")
        waitFor(app.buttons["tab.feed"], "exists == false", "the tab bar stayed over the compose page")
    }

    /// The kinds' icons wear the squad's scene colour, on every tab: on the track, its red, never
    /// the blue of a scene nobody picked (Tracy, 2026-11-23: the menu sat outside where the
    /// scene was set and fell back to the pool's blue).
    func testKindsWearTheSquadsScene() {
        let app = launch(language: "zh-Hans", size: "UICTContentSizeCategoryL", scene: "track")
        let plus = app.buttons["today.checkin"]
        XCTAssertTrue(plus.waitForExistence(timeout: Self.wait), "no ＋")
        for tab in ["tab.today", "tab.feed", "tab.me"] {
            app.buttons[tab].tap()
            plus.tap()
            let capsule = app.buttons["today.capsule.trained"]
            XCTAssertTrue(capsule.waitForExistence(timeout: Self.wait), "\(tab): the kinds didn't open")
            settle()
            keepScreenshot(named: "14d-checkin-menu-track-\(tab.dropFirst(4))")
            guard let ink = Self.mostColourful(in: capsule.screenshot().image) else {
                return XCTFail("\(tab): no coloured pixel in the 训练 capsule")
            }
            // The track's text colour is #B83325, so red well above blue; the pool's and the
            // gym's are blue above red.
            XCTAssertGreaterThan(ink.red, ink.blue + 0.25, "\(tab): the icon isn't the track's red: \(ink)")
            plus.tap()
            waitFor(capsule, "exists == false", "\(tab): the cross didn't put the kinds away")
        }
    }

    /// The most saturated pixel of a picture, in 0...1 channels: an icon's ink on clear glass.
    private static func mostColourful(in image: UIImage) -> (red: Double, green: Double, blue: Double)? {
        guard let picture = image.cgImage else { return nil }
        let (width, height) = (picture.width, picture.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(picture, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var (best, spread): ((UInt8, UInt8, UInt8)?, Int) = (nil, 40)
        for pixel in stride(from: 0, to: bytes.count, by: 4) {
            let (red, green, blue) = (bytes[pixel], bytes[pixel + 1], bytes[pixel + 2])
            let wider = Int(max(red, green, blue)) - Int(min(red, green, blue))
            if wider > spread { (best, spread) = ((red, green, blue), wider) }
        }
        return best.map { (Double($0.0) / 255, Double($0.1) / 255, Double($0.2) / 255) }
    }

    private func launch(language: String, size: String, scene: String? = nil) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-uitest-photos", "0", "-AppleLanguages", "(\(language))", "-AppleLocale", language,
            "-uitest-no-push", "-uitest-noon", "-today.cardPage", "0",
            "-UIPreferredContentSizeCategoryName", size, "-uitest-card-folded",
        ]
        if let scene { app.launchArguments += ["-uitest-scene", scene] }
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        return app
    }

    private func waitFor(_ element: XCUIElement, _ predicate: String, _ message: String) {
        let met = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [met], timeout: Self.wait), .completed, message)
    }

    private func settle() { Thread.sleep(forTimeInterval: 1) }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
