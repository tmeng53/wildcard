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

    /// 穿搭 opens on the shopping street: a closed store says how it opens and WARM-UP lets the
    /// person in, to a hoodie in the third color, a cap and the belt bag, then the cap off again.
    func testShoppingForClothes() {
        let app = launch(language: "zh-Hans")
        XCTAssertTrue(app.buttons["editor.done"].waitForExistence(timeout: Self.wait), "the editor never appeared")
        app.buttons["editor.tab.outfit"].tap()
        let warmup = app.buttons["editor.store.warmup"]
        XCTAssertTrue(warmup.waitForExistence(timeout: Self.wait), "no WARM-UP on the street")
        settle()
        keepScreenshot(named: "22-editor-street")
        let lap = app.buttons["editor.store.lap"]
        scrollUntilHittable(lap, in: app)
        lap.tap()
        let closed = app.descendants(matching: .any).matching(identifier: "editor.store.closed").firstMatch
        XCTAssertTrue(closed.waitForExistence(timeout: Self.wait), "a closed store didn't say how it opens")
        XCTAssertTrue(closed.label.contains("跑步打卡 3 次开门"), closed.label)
        XCTAssertFalse(app.buttons["editor.store.back"].exists, "a closed store let the person in")
        settle()
        keepScreenshot(named: "22b-editor-store-closed")

        scrollUntilHittable(warmup, in: app)
        warmup.tap()
        let hoodie = app.buttons["editor.tile.top.warmup-hoodie"]
        XCTAssertTrue(hoodie.waitForExistence(timeout: Self.wait), "no 连帽卫衣 on WARM-UP's rack")
        hoodie.tap()
        waitUntilSelected(hoodie, "picking 连帽卫衣 didn't select it")
        app.buttons["editor.swatch.top.2"].tap()
        waitUntilSelected(app.buttons["editor.swatch.top.2"], "the top swatch didn't select")
        settle()
        keepScreenshot(named: "22c-editor-store")
        // Hats and accessories come after the tops, bottoms and shoes, below the fold; a second
        // tap on a hat takes it off.
        let cap = app.buttons["editor.tile.hat.warmup-cap"]
        scrollUntilHittable(cap, in: app)
        cap.tap()
        waitUntilSelected(cap, "picking 棒球帽 didn't select it")
        let waistbag = app.buttons["editor.tile.acc.warmup-waistbag"]
        scrollUntilHittable(waistbag, in: app)
        waistbag.tap()
        waitUntilSelected(waistbag, "picking 运动腰包 didn't select it")
        settle()
        keepScreenshot(named: "22d-editor-outfit")
        scrollUntilHittable(cap, in: app)
        cap.tap()
        waitFor(cap, "isSelected == false", "a second tap didn't take the cap off")

        app.buttons["editor.store.back"].tap()
        XCTAssertTrue(warmup.waitForExistence(timeout: Self.wait), "← 商店街 didn't go back to the street")
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

    /// A cat wears no hair or person's face, so 发型 and 脸 go away; 就这样 waits for a nickname.
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
        XCTAssertFalse(app.buttons["editor.tab.face"].exists, "a cat still shows 脸")
        settle()
        keepScreenshot(named: "26-editor-cat")

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
        waitFor(done, "isEnabled == false", "就这样 is on with no nickname")
        nickname.typeText("小汤")
        waitFor(done, "isEnabled == true", "就这样 stays off with a nickname")
        XCTAssertEqual(undo.frame.minY, headerTop, accuracy: 1, "the keyboard moved the header")
        XCTAssertTrue(done.isHittable, "the keyboard covers 就这样")
        nickname.typeText("\n")
        waitFor(app.keyboards.element, "exists == false", "Return left the keyboard up")
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
        let warmup = app.buttons["editor.store.warmup"]
        XCTAssertTrue(warmup.waitForExistence(timeout: Self.wait), "no WARM-UP on the street")
        warmup.tap()
        let back = app.buttons["editor.store.back"]
        XCTAssertTrue(back.waitForExistence(timeout: Self.wait), "WARM-UP didn't open")
        XCTAssertTrue(back.label.contains("Shopping street"), back.label)
        XCTAssertEqual(app.buttons["editor.tile.top.warmup-hoodie"].label, "Hoodie")
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
        // Clear of 就这样 too: a tile under the bottom bar is "hittable" but the tap lands on the button.
        let done = app.buttons["editor.done"]
        func inView() -> Bool { element.exists && element.isHittable && element.frame.maxY < done.frame.minY }
        for _ in 0..<12 where !inView() {
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
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
