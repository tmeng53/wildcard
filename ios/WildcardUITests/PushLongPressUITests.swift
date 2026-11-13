import XCTest

/// The 6pm push long-pressed on the home screen, as a member does: the system opens the
/// `WildcardPushReact` content extension over it, which must draw the day (or, for a push it
/// can't read, the push's own words) and size itself to it. `DailyPushUITests` checks the view
/// through the app's preview; this checks the extension itself runs.
///
/// Showing a notification needs the permission, which `NotificationPromptUITests` expects not to
/// have been asked yet; XCTest runs the classes in name order, so that one runs first.
@MainActor
final class PushLongPressUITests: XCTestCase {
    private static let wait: TimeInterval = 30
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    /// A push carrying teammates' check-ins today: the view draws them, the teammate who patted
    /// first.
    func testTheDailyPushOpensTheDay() throws {
        continueAfterFailure = false
        let expanded = try longPress(Self.payload(today: Self.today), shot: "90-push-long-press-day")
        XCTAssertTrue(
            expanded.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "阿杰")).firstMatch
                .waitForExistence(timeout: Self.wait),
            "the long-pressed push doesn't show 阿杰's post:\n\(springboard.debugDescription.prefix(4000))")
        // In the app's language (Chinese here), not the simulator's: the extension is a process of
        // its own, which the launch arguments don't reach. The push's own words, which the system
        // keeps in the tree, say 本周小队已练 too, so the check is on the view's own words.
        XCTAssertTrue(
            expanded.descendants(matching: .any).matching(identifier: "pushReact.zh-Hans").firstMatch.exists,
            "the long-pressed push's view doesn't speak the app's language:\n\(springboard.debugDescription.prefix(4000))"
        )
        for english in ["Squad this week", "Strength", "TODAY"] {
            XCTAssertFalse(
                expanded.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", english)).firstMatch.exists,
                "the long-pressed push shows \(english):\n\(springboard.debugDescription.prefix(4000))")
        }
    }

    /// A push without `today` (as admins' test pushes are): the view shows its words.
    func testAPushWithoutTheDayShowsItsWords() throws {
        continueAfterFailure = false
        let expanded = try longPress(Self.payload(today: nil), shot: "91-push-long-press-words")
        // The system's own banner shows the same words, so the check is on the extension's view.
        let plain = expanded.descendants(matching: .any).matching(identifier: "pushReact.plain").firstMatch
        XCTAssertTrue(
            plain.waitForExistence(timeout: Self.wait),
            "the long-pressed push doesn't draw its words:\n\(springboard.debugDescription.prefix(4000))")
        XCTAssertTrue(plain.label.contains("测试队友"), "the extension's words aren't the push's: \(plain.label)")
    }

    /// Launches the app with the push, goes home, long-presses its banner and keeps a screenshot
    /// of what opens.
    private func longPress(_ payload: [String: Any], shot: String) throws -> XCUIApplication {
        let app = XCUIApplication()
        let json = try XCTUnwrap(String(bytes: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8))
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-push", json,
        ]
        // Home opens on the folded capsule, as these tests were written for.
        app.launchArguments.append("-uitest-card-folded")
        app.launch()
        // The system prompt's second button allows, in any language; it shows only the first time.
        let allow = springboard.alerts.firstMatch
        if allow.waitForExistence(timeout: 5) {
            allow.buttons.element(boundBy: 1).tap()
        }
        XCUIDevice.shared.press(.home)
        let banner = springboard.buttons.matching(NSPredicate(format: "label CONTAINS %@", "测试队友")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: Self.wait), "no banner for the 6pm push")
        banner.press(forDuration: 1.5)
        // The extension starts, draws and resizes its card.
        Thread.sleep(forTimeInterval: 4)
        keepScreenshot(named: shot)
        let tree = XCTAttachment(string: springboard.debugDescription)
        tree.name = "\(shot)-tree"
        tree.lifetime = .keepAlways
        add(tree)
        return springboard
    }

    private static let viewer = "0b1c2d3e-0000-4000-8000-000000000000"

    /// Today as the server sends it (`api/apps/server/src/flows/daily-push-today.ts`).
    private static let today: [String: Any] = [
        "members": [
            ["id": viewer],
            ["id": "0b1c2d3e-0000-4000-8000-000000000001", "name": "阿杰"],
            ["id": "0b1c2d3e-0000-4000-8000-000000000002", "name": "测试队友"],
        ],
        "posts": [
            [
                "id": "1a2b3c4d-0000-4000-8000-000000000001", "by": 1, "kind": "trained", "sport": "strength",
                "minutes": 45, "at": "2026-10-23T17:42:00.000Z", "text": "腿练完了", "reactions": [[2, "💪"]],
                "reactionCount": 1,
            ]
        ],
        "more": 0,
        "pokedBy": [2],
    ]

    /// The 6pm push naming the teammate who patted, as `push-samples.json`'s, with `today` or not.
    private static func payload(today: [String: Any]?) -> [String: Any] {
        var event: [String: Any] = [
            "kind": "dailyProgress", "day": "2026-10-23", "squad": "6f1c2a5e-8d3b-4f7a-9c2e-1b4d5a6e7f80",
            "squadTrainedDays": 3, "squadPlannedDays": 5, "received": ["poke": 1],
        ]
        event["today"] = today
        return [
            "version": 1,
            "aps": [
                "alert": ["loc-key": "push.dailyProgress.poke", "loc-args": ["3", "5", "测试队友"]],
                "category": "dailyProgress", "thread-id": "dailyProgress", "mutable-content": 1,
            ],
            "event": event,
        ]
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
