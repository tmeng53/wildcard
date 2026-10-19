import XCTest

/// Dresses the character the way a person does in sign-up and keeps screenshots for review.
/// The editor opens on its own (`-character-editor`) until sign-up wires it in, from a fixed
/// look (`-character-editor-sample`): a person with a bob, a tee, shorts and a dumbbell.
@MainActor
final class CharacterEditorUITests: XCTestCase {
    /// How long a check waits for the UI. A busy CI runner can take seconds per accessibility
    /// query; a wait that succeeds returns as soon as it does.
    private static let wait: TimeInterval = 30

    /// Sign-up opens on 样子 with the step, the person picked and nothing to undo yet.
    func testOpeningInSignUp() {
        let app = launch(language: "zh-Hans")
        let done = app.buttons["editor.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.wait), "the editor never appeared")
        XCTAssertEqual(done.label, "就这样")
        let steps = app.descendants(matching: .any).matching(identifier: "editor.steps").firstMatch
        XCTAssertEqual(steps.label, "第 2 步，共 4 步")
        XCTAssertTrue(app.buttons["editor.tile.body.peach"].isSelected, "the sample isn't a person")
        XCTAssertFalse(app.buttons["editor.undo"].isEnabled, "undo is on before any change")
        settle()
        keepScreenshot(named: "20-editor-look")
    }

    /// 卷发 in the fourth hair color, then a hoodie in the third top color and a cap.
    func testPickingHairAndClothes() {
        let app = launch(language: "zh-Hans")
        XCTAssertTrue(app.buttons["editor.done"].waitForExistence(timeout: Self.wait), "the editor never appeared")
        app.buttons["editor.tab.hair"].tap()
        let curls = app.buttons["editor.tile.hair.curls"]
        XCTAssertTrue(curls.waitForExistence(timeout: Self.wait), "no 卷发 tile")
        XCTAssertTrue(app.buttons["editor.tile.hair.bob"].isSelected)
        curls.tap()
        waitUntilSelected(curls, "picking 卷发 didn't select it")
        app.buttons["editor.swatch.hair.3"].tap()
        waitUntilSelected(app.buttons["editor.swatch.hair.3"], "the hair swatch didn't select")
        XCTAssertTrue(app.buttons["editor.undo"].isEnabled)
        settle()
        keepScreenshot(named: "21-editor-hair")

        app.buttons["editor.tab.outfit"].tap()
        let hoodie = app.buttons["editor.tile.top.hoodie"]
        XCTAssertTrue(hoodie.waitForExistence(timeout: Self.wait), "no 卫衣 tile")
        hoodie.tap()
        waitUntilSelected(hoodie, "picking 卫衣 didn't select it")
        app.buttons["editor.swatch.top.2"].tap()
        app.buttons["editor.tile.hat.cap"].tap()
        settle()
        keepScreenshot(named: "22-editor-outfit")
    }

    /// The racket plays its move; undo brings the dumbbell back. No basketball this release.
    func testPickingAPropAndUndoing() {
        let app = launch(language: "zh-Hans")
        XCTAssertTrue(app.buttons["editor.done"].waitForExistence(timeout: Self.wait), "the editor never appeared")
        app.buttons["editor.tab.prop"].tap()
        let racket = app.buttons["editor.tile.prop.racket"]
        XCTAssertTrue(racket.waitForExistence(timeout: Self.wait), "no 网球拍 tile")
        XCTAssertTrue(app.buttons["editor.tile.prop.dumbbell"].isSelected)
        XCTAssertFalse(app.buttons["editor.tile.prop.basketball"].exists, "the basketball isn't in this release")
        racket.tap()
        waitUntilSelected(racket, "picking 网球拍 didn't select it")
        settle()
        keepScreenshot(named: "23-editor-prop")
        app.buttons["editor.undo"].tap()
        waitUntilSelected(app.buttons["editor.tile.prop.dumbbell"], "undo didn't bring the dumbbell back")
    }

    /// The carousel starts on 高能量; the next name along is in view, and tapping it brings it to
    /// the middle and picks it.
    func testPickingAPersona() {
        let app = launch(language: "zh-Hans")
        XCTAssertTrue(app.buttons["editor.done"].waitForExistence(timeout: Self.wait), "the editor never appeared")
        app.buttons["editor.tab.persona"].tap()
        let energetic = app.buttons["editor.persona.energetic"]
        XCTAssertTrue(energetic.waitForExistence(timeout: Self.wait), "no persona carousel")
        XCTAssertTrue(energetic.isSelected, "高能量 isn't the starting persona")
        settle()
        keepScreenshot(named: "24-editor-persona")
        app.buttons["editor.persona.showoff"].tap()
        waitUntilSelected(app.buttons["editor.persona.showoff"], "tapping 显眼包 didn't pick it")
        settle()
        keepScreenshot(named: "25-editor-persona-showoff")
    }

    /// A cat wears no hair, so 发型 goes away; 就这样 waits for a nickname.
    func testBecomingACatWithANickname() {
        let app = launch(language: "zh-Hans")
        let done = app.buttons["editor.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.wait), "the editor never appeared")
        app.buttons["editor.tab.look"].tap()
        let cat = app.buttons["editor.tile.body.cat"]
        XCTAssertTrue(cat.waitForExistence(timeout: Self.wait), "no cat tile")
        cat.tap()
        waitUntilSelected(cat, "picking the cat didn't select it")
        XCTAssertFalse(app.buttons["editor.tab.hair"].exists, "a cat still shows 发型")
        settle()
        keepScreenshot(named: "26-editor-cat")

        let nickname = app.textFields["editor.nickname"]
        nickname.tap()
        nickname.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5))
        XCTAssertFalse(done.isEnabled, "就这样 is on with no nickname")
        nickname.typeText("小汤")
        XCTAssertTrue(done.isEnabled, "就这样 stays off with a nickname")
        keepScreenshot(named: "27-editor-nickname")
    }

    func testChangingTheCharacterFromProfileInEnglish() {
        let app = launch(language: "en", profile: true)
        let save = app.buttons["editor.done"]
        XCTAssertTrue(save.waitForExistence(timeout: Self.wait), "the editor never appeared")
        XCTAssertEqual(save.label, "Save")
        XCTAssertEqual(app.buttons["editor.cancel"].label, "Cancel")
        XCTAssertEqual(app.buttons["editor.tab.look"].label, "Look")
        app.buttons["editor.tab.outfit"].tap()
        XCTAssertEqual(app.buttons["editor.tile.hat.none"].label, "No hat")
        settle()
        keepScreenshot(named: "28-editor-profile-en")
    }

    private func launch(language: String, profile: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", language]
        app.launchArguments += ["-character-editor", "-character-editor-sample"]
        if profile { app.launchArguments.append("-character-editor-profile") }
        app.launch()
        return app
    }

    /// Taps update the UI on the next frames; wait for the selection rather than checking at once.
    private func waitUntilSelected(
        _ element: XCUIElement, _ message: String, timeout: TimeInterval = CharacterEditorUITests.wait
    ) {
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [selected], timeout: timeout), .completed, message)
    }

    /// Lets thumbnails build and the character's one move finish before a screenshot.
    private func settle() {
        Thread.sleep(forTimeInterval: 2)
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
