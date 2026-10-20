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

        // Shoes sit at the bottom of 穿搭; the sample wears the rig's white sneakers.
        let climbing = app.buttons["editor.tile.shoes.climbing"]
        hoodie.swipeUp()
        XCTAssertTrue(climbing.waitForExistence(timeout: Self.wait), "no 攀岩鞋 tile")
        XCTAssertTrue(app.buttons["editor.tile.shoes.sneaker"].isSelected, "小白鞋 isn't what the sample wears")
        climbing.tap()
        waitUntilSelected(climbing, "picking 攀岩鞋 didn't select it")
        settle()
        keepScreenshot(named: "29-editor-shoes")
    }

    /// 脸: sleepy eyes in the third eye color, bold brows, a grin and round glasses.
    func testPickingAFace() {
        let app = launch(language: "zh-Hans")
        XCTAssertTrue(app.buttons["editor.done"].waitForExistence(timeout: Self.wait), "the editor never appeared")
        app.buttons["editor.tab.face"].tap()
        let sleepy = app.buttons["editor.tile.eyes.sleepy"]
        XCTAssertTrue(sleepy.waitForExistence(timeout: Self.wait), "no 困困眼 tile")
        XCTAssertTrue(app.buttons["editor.tile.eyes.round"].isSelected, "the rig's round eyes aren't picked")
        sleepy.tap()
        waitUntilSelected(sleepy, "picking 困困眼 didn't select it")
        app.buttons["editor.swatch.eyes.2"].tap()
        app.buttons["editor.tile.brows.bold"].tap()
        waitUntilSelected(app.buttons["editor.tile.brows.bold"], "picking 浓眉 didn't select it")
        settle()
        keepScreenshot(named: "30-editor-face")
        sleepy.swipeUp()
        app.buttons["editor.tile.mouth.grin"].tap()
        let glasses = app.buttons["editor.tile.glasses.round"]
        XCTAssertTrue(glasses.waitForExistence(timeout: Self.wait), "no 圆框 tile")
        glasses.tap()
        waitUntilSelected(glasses, "picking 圆框 didn't select it")
        settle()
        keepScreenshot(named: "31-editor-face-glasses")
    }

    /// The racket plays its move; undo brings the dumbbell back.
    func testPickingAPropAndUndoing() {
        let app = launch(language: "zh-Hans")
        XCTAssertTrue(app.buttons["editor.done"].waitForExistence(timeout: Self.wait), "the editor never appeared")
        app.buttons["editor.tab.prop"].tap()
        let racket = app.buttons["editor.tile.prop.racket"]
        XCTAssertTrue(racket.waitForExistence(timeout: Self.wait), "no 网球拍 tile")
        XCTAssertTrue(app.buttons["editor.tile.prop.dumbbell"].isSelected)
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
        // With no 口头禅 the bubble says the persona's own line.
        let shout = app.staticTexts["editor.shout"]
        XCTAssertTrue(shout.waitForExistence(timeout: Self.wait), "no speech bubble on 性格")
        XCTAssertEqual(shout.label, "冲冲冲！")
        app.buttons["editor.persona.showoff"].tap()
        waitUntilSelected(app.buttons["editor.persona.showoff"], "tapping 显眼包 didn't pick it")
        waitFor(shout, "label == '名场面'", "the bubble didn't take 显眼包's line")
        settle()
        keepScreenshot(named: "25-editor-persona-showoff")
    }

    /// A 口头禅 shows in the bubble as it is typed; past ten characters 就这样 waits.
    func testTypingACatchphrase() {
        let app = launch(language: "zh-Hans")
        let done = app.buttons["editor.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.wait), "the editor never appeared")
        app.buttons["editor.tab.persona"].tap()
        let field = app.textFields["editor.catchphrase"]
        XCTAssertTrue(field.waitForExistence(timeout: Self.wait), "no 口头禅 field")
        field.tap()
        field.typeText("冲就完了")
        let shout = app.staticTexts["editor.shout"]
        waitFor(shout, "label == '冲就完了'", "the bubble didn't show the 口头禅")
        settle()
        keepScreenshot(named: "32-editor-catchphrase")
        field.typeText("今天也要冲冲冲")
        XCTAssertFalse(done.exists && done.isHittable, "就这样 shows over the keyboard")
        field.typeText("\n")
        waitFor(done, "isEnabled == false", "就这样 is on with an eleven-character 口头禅")
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
        // The first tap on a field puts the cursor after its text; delete more than it holds.
        nickname.tap()
        nickname.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12))
        waitFor(done, "isEnabled == false", "就这样 is on with no nickname")
        nickname.typeText("小汤")
        waitFor(done, "isEnabled == true", "就这样 stays off with a nickname")
        keepScreenshot(named: "27-editor-nickname")
    }

    func testChangingTheCharacterFromProfileInEnglish() {
        let app = launch(language: "en", profile: true)
        let save = app.buttons["editor.done"]
        XCTAssertTrue(save.waitForExistence(timeout: Self.wait), "the editor never appeared")
        XCTAssertEqual(save.label, "Save")
        XCTAssertEqual(app.buttons["editor.cancel"].label, "Cancel")
        XCTAssertTrue(app.staticTexts["My character"].exists, "no page title from 我")
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
        // Close the app when the test ends, so the next launch never has to stop it: a busy
        // simulator sometimes fails to ("Failed to terminate").
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        return app
    }

    /// Taps update the UI on the next frames; wait for the selection rather than checking at once.
    private func waitUntilSelected(
        _ element: XCUIElement, _ message: String, timeout: TimeInterval = CharacterEditorUITests.wait
    ) {
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [selected], timeout: timeout), .completed, message)
    }

    private func waitFor(_ element: XCUIElement, _ predicate: String, _ message: String) {
        let met = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [met], timeout: Self.wait), .completed, message)
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
