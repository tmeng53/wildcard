import XCTest

/// The home scene at every squad size, kept as screenshots for review: everyone drawn whole on
/// the screen and nobody standing on the track's lane lines.
@MainActor
final class SquadSceneUITests: XCTestCase {
    func testTrackWithOneFourAndEightMembers() {
        continueAfterFailure = false
        for size in [1, 4, 8] {
            let app = XCUIApplication()
            app.launchArguments += [
                "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-uitest-noon",
                "-today.cardPage", "0", "-uitest-squad", "\(size)", "-uitest-scene", "track",
            ]
            app.launch()
            let card = app.descendants(matching: .any).matching(identifier: "today.card").firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 30), "今天 never appeared")
            // Lets springs and the characters' entrances settle.
            Thread.sleep(forTimeInterval: 0.8)
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "21-today-track-squad-\(size)"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }
}
