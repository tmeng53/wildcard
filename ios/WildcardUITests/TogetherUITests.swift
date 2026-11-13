import XCTest

/// The squad celebrating together on the home, the way a person meets it on opening the app:
/// 人浪 when the week's goal is reached, 叠罗汉 when two teammates ran today, 撞头 when I trained
/// too. Frames of each are kept, named with when each was taken, for review; the home's card and
/// the 打卡 button stay in place throughout. In the pairs someone walks over, so the figures don't
/// all stand still.
@MainActor
final class TogetherUITests: XCTestCase {
    /// Slow CI simulators can take many seconds to show a screen; a real failure still fails.
    private static let wait: TimeInterval = 30

    func testTheWave() {
        celebrate("wave", frames: "61-wave")
    }

    func testTheStack() {
        celebrate("stack", frames: "62-stack", walks: true)
    }

    func testTheBump() {
        celebrate("bump", frames: "63-bump", walks: true)
    }

    private func celebrate(_ kind: String, frames name: String, walks: Bool = false) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon",
            "-today.cardPage", "0", "-uitest-card-folded", "-uitest-together", kind,
        ]
        app.launch()
        let card = app.descendants(matching: .any).matching(identifier: "today.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: Self.wait), "今天 never appeared")
        let opened = Date()
        var places: Set<String> = []
        for frame in 0..<16 {
            // Every frame is sampled, before its screenshot: on a slow simulator the walk-over can
            // start late, and it is over in a few seconds.
            if walks, let now = figurePlaces(in: app) { places.insert(now) }
            let after = Int(Date().timeIntervalSince(opened) * 1000)
            keepScreenshot(named: String(format: "\(name)-%02d-%05dms", frame, after))
            Thread.sleep(forTimeInterval: 0.35)
        }
        XCTAssertTrue(card.isHittable, "the squad card went away during the celebration")
        if walks { XCTAssertGreaterThan(places.count, 1, "nobody walked over: the \(kind) didn't play") }
    }

    /// Where every figure on the scene stands, from one snapshot of the app: reading each
    /// figure's frame on its own costs a query each, which on a busy CI simulator took the 撞头's
    /// few seconds (nine a sample) and missed it. Nil when the snapshot failed.
    private func figurePlaces(in app: XCUIApplication) -> String? {
        guard let root = try? app.snapshot() else { return nil }
        var places: [String] = []
        var pending: [any XCUIElementSnapshot] = [root]
        while let element = pending.popLast() {
            if ["today.me", "today.mate"].contains(element.identifier) {
                places.append("\(Int(element.frame.midX)),\(Int(element.frame.maxY))")
            }
            pending += element.children
        }
        return places.sorted().joined(separator: " ")
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
