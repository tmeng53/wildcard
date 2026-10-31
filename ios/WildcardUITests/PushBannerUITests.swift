import XCTest

/// Every push the server sends, as the member sees it: each sample in `push-samples.json` (which
/// the API writes from its own push code, with the longest names a push can carry) is shown as a
/// banner on the home screen in Chinese, then tapped, which must open the screen the push points
/// at. Keeps a screenshot of each for review.
///
/// Showing a notification needs the permission, which `NotificationPromptUITests` expects not to
/// have been asked yet; XCTest runs the classes in name order, so that one runs first.
@MainActor
final class PushBannerUITests: XCTestCase {
    private static let wait: TimeInterval = 30
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    /// Each sample, the tab its tap opens, and the screenshot's number.
    private static let samples: [(key: String, opens: String, shot: Int)] = [
        ("push.dailyProgress", "tab.today", 82),
        ("push.dailyProgress.received", "tab.today", 83),
        ("push.dailyProgress.poke", "tab.today", 84),
        ("push.dailyProgress.poke.more", "tab.today", 85),
        ("push.weeklyAwards.ready", "tab.feed", 86),
        ("push.weeklyAwards.stuck", "tab.today", 87),
    ]

    func testEveryPushShowsItsWordsAndOpensItsScreen() throws {
        continueAfterFailure = false
        let payloads = try Self.payloads()
        let catalog = try Self.chineseCatalog()
        XCTAssertEqual(Set(payloads.keys), Set(Self.samples.map(\.key)), "a push has no case here")

        for sample in Self.samples {
            let payload = try XCTUnwrap(payloads[sample.key])
            let words = try Self.words(of: payload, in: catalog)
            let app = XCUIApplication()
            // Open on 我, so the tap has somewhere to move from.
            app.launchArguments += [
                "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-tab", "me",
                "-uitest-push", try Self.json(payload),
            ]
            app.launch()
            let allow = springboard.alerts.firstMatch
            // The system prompt's second button allows, in any language; it shows only the first time.
            if allow.waitForExistence(timeout: 5) { allow.buttons.element(boundBy: 1).tap() }

            XCUIDevice.shared.press(.home)
            let banner = self.banner(showing: words)
            keepScreenshot(named: "\(sample.shot)-push-\(sample.key.replacingOccurrences(of: ".", with: "-"))")
            banner.tap()
            XCTAssertTrue(
                app.wait(for: .runningForeground, timeout: Self.wait),
                "\(sample.key) didn't open the app (state \(app.state.rawValue)) after tapping "
                    + "\(banner.debugDescription.prefix(300))")
            waitFor(app.buttons[sample.opens], "isSelected == true", "\(sample.key) didn't open \(sample.opens)")
            app.terminate()
        }
    }

    /// The banner with these words on the home screen (it arrives a few seconds after launch). The
    /// banner itself is a button; the words alone are a text inside it.
    private func banner(showing words: String) -> XCUIElement {
        let banner = springboard.buttons.matching(NSPredicate(format: "label CONTAINS %@", words)).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: Self.wait), "no banner reading「\(words)」")
        return banner
    }

    /// What iOS shows for a payload: its `loc-key`'s Chinese line with `loc-args` in its placeholders.
    private static func words(of payload: [String: Any], in catalog: [String: String]) throws -> String {
        let alert = try XCTUnwrap((payload["aps"] as? [String: Any])?["alert"] as? [String: Any])
        let key = try XCTUnwrap(alert["loc-key"] as? String)
        var line = try XCTUnwrap(catalog[key], "\(key) has no Chinese line")
        for (index, argument) in (alert["loc-args"] as? [String] ?? []).enumerated() {
            line = line.replacingOccurrences(of: "%\(index + 1)$@", with: argument)
        }
        return line
    }

    private static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

    private static func payloads() throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: repository.appendingPathComponent("push-samples.json"))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]])
    }

    /// The app's String Catalog, each key's `zh-Hans` line.
    private static func chineseCatalog() throws -> [String: String] {
        let file = repository.deletingLastPathComponent().appendingPathComponent("Wildcard/Localizable.xcstrings")
        let catalog = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let strings = try XCTUnwrap(catalog["strings"] as? [String: [String: Any]])
        return strings.compactMapValues { entry in
            let localizations = entry["localizations"] as? [String: [String: Any]]
            return (localizations?["zh-Hans"]?["stringUnit"] as? [String: Any])?["value"] as? String
        }
    }

    private static func json(_ payload: [String: Any]) throws -> String {
        try XCTUnwrap(String(bytes: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8))
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
