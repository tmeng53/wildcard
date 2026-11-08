import XCTest

/// Dresses the character the way a person does in sign-up and keeps screenshots for review.
/// The editor opens on its own (`-character-editor`) until sign-up wires it in, from a fixed
/// look (`-character-editor-sample`): a person with a bob, a tee, shorts and a dumbbell.
@MainActor
final class CharacterEditorUITests: XCTestCase {
    /// How long a check waits for the UI. A busy CI runner can take seconds per accessibility
    /// query; a wait that succeeds returns as soon as it does.
    private static let wait: TimeInterval = 30

    /// Sign-up opens on 长相 with the step, the person picked and nothing to undo yet.
    func testOpeningInSignUp() {
        let app = launch(language: "zh-Hans")
        let done = app.buttons["editor.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.wait), "the editor never appeared")
        XCTAssertEqual(done.label, "确认")
        let steps = app.descendants(matching: .any).matching(identifier: "editor.steps").firstMatch
        XCTAssertEqual(steps.label, "第 2 步，共 5 步")
        XCTAssertTrue(app.buttons["editor.tile.body.peach"].isSelected, "the sample isn't a person")
        XCTAssertFalse(app.buttons["editor.undo"].isEnabled, "undo is on before any change")
        settle()
        keepScreenshot(named: "20-editor-look")
    }

    /// 卷发 in the fourth hair color.
    func testPickingHair() {
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
    }

    /// 穿搭 is 我的衣橱: what the member owns, one slot at a time (WARM-UP's starters here), no stores
    /// and no locks; a hoodie in the third color, a cap and the belt bag, then the cap off again.
    func testDressingFromTheWardrobe() {
        let app = launch(language: "zh-Hans")
        XCTAssertTrue(app.buttons["editor.done"].waitForExistence(timeout: Self.wait), "the editor never appeared")
        app.buttons["editor.tab.outfit"].tap()
        let hoodie = app.buttons["editor.tile.top.warmup-hoodie"]
        XCTAssertTrue(hoodie.waitForExistence(timeout: Self.wait), "no 连帽卫衣 in the wardrobe")
        XCTAssertFalse(app.buttons["street.store.warmup"].exists, "the wardrobe still shows the street")
        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: "editor.mystery.top").firstMatch.exists,
            "the wardrobe shows a locked box")
        settle()
        keepScreenshot(named: "22-editor-wardrobe")
        hoodie.tap()
        waitUntilSelected(hoodie, "picking 连帽卫衣 didn't select it")
        app.buttons["editor.swatch.top.2"].tap()
        waitUntilSelected(app.buttons["editor.swatch.top.2"], "the top swatch didn't select")
        settle()
        keepScreenshot(named: "22-editor-store")
        // One slot shows at a time: 上衣 only, until 头饰 is picked on the wardrobe's bar.
        let cap = app.buttons["editor.tile.hat.warmup-cap"]
        XCTAssertFalse(cap.exists, "头饰 shows with 上衣")
        app.buttons["editor.wardrobe.hat"].tap()
        XCTAssertTrue(cap.waitForExistence(timeout: Self.wait), "no 棒球帽 under 头饰")
        XCTAssertFalse(hoodie.exists, "上衣 still shows under 头饰")
        scrollUntilHittable(cap, in: app)
        cap.tap()
        waitUntilSelected(cap, "picking 棒球帽 didn't select it")
        XCTAssertTrue(app.buttons["editor.swatch.hat.0"].isHittable, "the hat's colors aren't above the wardrobe")
        let waistbag = app.buttons["editor.tile.acc.warmup-waistbag"]
        app.buttons["editor.wardrobe.acc"].tap()
        XCTAssertTrue(waistbag.waitForExistence(timeout: Self.wait), "no 运动腰包 under 配饰")
        scrollUntilHittable(waistbag, in: app)
        waistbag.tap()
        waitUntilSelected(waistbag, "picking 运动腰包 didn't select it")
        settle()
        keepScreenshot(named: "22-editor-outfit")
        // A second tap on the cap takes it off.
        app.buttons["editor.wardrobe.hat"].tap()
        scrollUntilHittable(cap, in: app)
        cap.tap()
        waitFor(cap, "isSelected == false", "a second tap didn't take the cap off")
    }

    /// 脸 opens on the rig's round eyes; 星星眼 in the third eye color, then 坏笑 and round
    /// glasses further down.
    func testPickingAFace() {
        let app = launch(language: "zh-Hans")
        XCTAssertTrue(app.buttons["editor.done"].waitForExistence(timeout: Self.wait), "the editor never appeared")
        app.buttons["editor.tab.face"].tap()
        let sparkle = app.buttons["editor.tile.eyes.sparkle"]
        XCTAssertTrue(sparkle.waitForExistence(timeout: Self.wait), "no 星星眼 tile")
        XCTAssertTrue(app.buttons["editor.tile.eyes.round"].isSelected, "the rig's round eyes aren't picked")
        sparkle.tap()
        waitUntilSelected(sparkle, "picking 星星眼 didn't select it")
        app.buttons["editor.swatch.eyes.2"].tap()
        waitUntilSelected(app.buttons["editor.swatch.eyes.2"], "the eye swatch didn't select")
        settle()
        keepScreenshot(named: "29-editor-face")

        // Sign-up's title above the editor leaves the brows below the fold, where the grid
        // hasn't made their tiles yet.
        let softBrows = app.buttons["editor.tile.brows.soft"]
        scrollUntilHittable(softBrows, in: app)
        XCTAssertTrue(softBrows.isSelected, "the sample's brows aren't picked")
        let smirk = app.buttons["editor.tile.mouth.smirk"]
        scrollUntilHittable(smirk, in: app)
        smirk.tap()
        waitUntilSelected(smirk, "picking 坏笑 didn't select it")
        let glasses = app.buttons["editor.tile.glasses.round"]
        scrollUntilHittable(glasses, in: app)
        XCTAssertTrue(app.buttons["editor.tile.glasses.none"].isSelected, "the sample wears glasses")
        glasses.tap()
        waitUntilSelected(glasses, "picking 圆框 didn't select it")
        settle()
        keepScreenshot(named: "30-editor-face-glasses")
    }

    /// The tumbler, the other prop every member starts with, plays its move; undo brings the
    /// dumbbell back.
    func testPickingAPropAndUndoing() {
        let app = launch(language: "zh-Hans")
        XCTAssertTrue(app.buttons["editor.done"].waitForExistence(timeout: Self.wait), "the editor never appeared")
        app.buttons["editor.tab.prop"].tap()
        let bottle = app.buttons["editor.tile.prop.bottle"]
        XCTAssertTrue(bottle.waitForExistence(timeout: Self.wait), "no 外卡水杯 tile")
        XCTAssertTrue(app.buttons["editor.tile.prop.dumbbell"].isSelected)
        bottle.tap()
        waitUntilSelected(bottle, "picking 外卡水杯 didn't select it")
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

    /// A cat wears no hair, so 发型 goes away, but it changes its face on 脸 like a person; 确认
    /// waits for a nickname.
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
        app.buttons["editor.tab.face"].tap()
        let sparkle = app.buttons["editor.tile.eyes.sparkle"]
        XCTAssertTrue(sparkle.waitForExistence(timeout: Self.wait), "a cat has no 脸 to change")
        sparkle.tap()
        waitUntilSelected(sparkle, "picking 星星眼 on a cat didn't select it")
        settle()
        keepScreenshot(named: "26-editor-cat-face")
        app.buttons["editor.tab.look"].tap()

        let nickname = app.textFields["editor.nickname"]
        // The name sits on the ticket's stub, under the tear line (44 above the ticket's bottom),
        // centred on the ticket.
        let stage = app.otherElements["editor.stage"].frame
        let field = nickname.frame
        XCTAssertGreaterThanOrEqual(field.minY, stage.maxY - 44, "the nickname rose above the tear line")
        XCTAssertLessThanOrEqual(field.maxY, stage.maxY, "the nickname fell off the ticket")
        XCTAssertEqual(field.midY, stage.maxY - 22, accuracy: 1, "the nickname isn't centred on the stub")
        // XCUITest reports the field about 8 points right of the ticket's middle while the name
        // draws centred (CI's 26-editor-cat), so this checks the name stays near the middle.
        XCTAssertEqual(field.midX, stage.midX, accuracy: 12, "the nickname isn't centred on the ticket")
        let undo = app.buttons["editor.undo"]
        let headerTop = undo.frame.minY
        // The first tap on a field puts the cursor after its text; delete more than it holds.
        nickname.tap()
        nickname.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12))
        // While the name is typed the button is 好了: it only puts the keyboard away, never
        // finishes the character.
        let named = app.buttons["editor.named"]
        XCTAssertTrue(named.waitForExistence(timeout: Self.wait), "the button isn't 好了 while typing")
        XCTAssertFalse(done.exists, "确认 shows while the nickname is typed")
        XCTAssertTrue(named.isHittable, "the keyboard covers 好了")
        named.tap()
        waitFor(app.keyboards.element, "exists == false", "好了 left the keyboard up")
        waitFor(done, "isEnabled == false", "确认 is on with no nickname")
        nickname.tap()
        nickname.typeText("小汤")
        XCTAssertEqual(undo.frame.minY, headerTop, accuracy: 1, "the keyboard moved the header")
        keepScreenshot(named: "27-editor-nickname")
        nickname.typeText("\n")
        waitFor(app.keyboards.element, "exists == false", "Return left the keyboard up")
        waitFor(done, "isEnabled == true", "确认 stays off with a nickname")
    }

    func testChangingTheCharacterFromProfileInEnglish() {
        let app = launch(language: "en", profile: true)
        let save = app.buttons["editor.done"]
        XCTAssertTrue(save.waitForExistence(timeout: Self.wait), "the editor never appeared")
        XCTAssertEqual(save.label, "Save")
        XCTAssertEqual(app.buttons["editor.cancel"].label, "Cancel")
        XCTAssertEqual(app.buttons["editor.tab.look"].label, "Looks")
        app.buttons["editor.tab.outfit"].tap()
        let hoodie = app.buttons["editor.tile.top.warmup-hoodie"]
        XCTAssertTrue(hoodie.waitForExistence(timeout: Self.wait), "no hoodie in the wardrobe")
        XCTAssertEqual(hoodie.label, "Hoodie")
        // The wardrobe's bar names each slot in the app's language.
        XCTAssertEqual(app.buttons["editor.wardrobe.top"].label, "Tops")
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

    /// Scrolls the choices a little at a time until `element` can be tapped: the grid only
    /// makes the tiles in view, and one under the done bar can't be tapped. The drag starts
    /// low on the screen, in the choices and clear of the stage above, and holds at the end so
    /// the list doesn't coast: a tap while it coasts only stops it.
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
        // Clear of 确认 too: a tile under the bottom bar is "hittable" but the tap lands on the button.
        let done = app.buttons["editor.done"]
        func inView() -> Bool { element.exists && element.isHittable && element.frame.maxY < done.frame.minY }
        // The rack holds every store's pieces now, so the hat row can sit a long way down.
        // A tile scrolled past, above the view, comes back with a drag the other way.
        func isAbove() -> Bool { element.exists && element.frame.maxY < app.frame.midY }
        for _ in 0..<24 where !inView() {
            if isAbove() {
                end.press(forDuration: 0.05, thenDragTo: start, withVelocity: .slow, thenHoldForDuration: 0.3)
            } else {
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
            }
        }
        XCTAssertTrue(inView(), "\(element.identifier) never scrolled into view")
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
