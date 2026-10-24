import XCTest

/// Walks sign-up the way a new member does (`-onboarding`, with the in-memory squad) and keeps
/// a screenshot of every step, plus frames of 上场 a few times a second to review its motion.
@MainActor
final class SignUpUITests: XCTestCase {
    /// How long a check waits for the UI. A busy CI runner can take seconds per accessibility
    /// query; a wait that succeeds returns as soon as it does.
    private static let wait: TimeInterval = 30

    /// Open screen, 角色和昵称, a squad joined by code, two sports, the week, then 上场 and home.
    func testJoiningASquad() {
        let app = launch(language: "zh-Hans")
        let signIn = app.buttons["signup.signIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: Self.wait), "the open screen never appeared")
        settle()
        keepScreenshot(named: "40-signup-open")
        // The whole crowd stands above the sign-in button, feet included.
        let crowd = app.buttons.matching(identifier: "signup.crowd").allElementsBoundByIndex
        XCTAssertEqual(crowd.count, 5, "the open screen shows five characters")
        for member in crowd {
            XCTAssertLessThanOrEqual(member.frame.maxY, signIn.frame.minY, "the sign-in button covers a character")
        }
        XCTAssertTrue(app.links["用户协议"].exists, "the terms line has no link to the terms")
        XCTAssertTrue(app.links["隐私政策"].exists, "the terms line has no link to the privacy policy")
        signIn.tap()
        makeCharacter(in: app)
        joinBySquadCode(in: app)
        pickSports(in: app)
        planTheWeek(in: app)
        watchTheEntrance(in: app)
    }

    private func makeCharacter(in app: XCUIApplication) {
        let editorDone = app.buttons["editor.done"]
        XCTAssertTrue(editorDone.waitForExistence(timeout: Self.wait), "角色和昵称 never appeared")
        XCTAssertTrue(app.staticTexts["创建你的外卡运动员"].exists, "step 1 has no title")
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "editor.steps").firstMatch.label, "第 1 步，共 4 步")
        let nickname = app.textFields["editor.nickname"]
        nickname.tap()
        nickname.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12))
        // Return puts the keyboard away: the editor doesn't make room for it, so it covers 就这样.
        nickname.typeText("Tracy\n")
        waitFor(editorDone, "isEnabled == true", "就这样 stays off with a nickname")
        settle()
        keepScreenshot(named: "41-signup-character")
        editorDone.tap()
    }

    private func joinBySquadCode(in app: XCUIApplication) {
        let join = app.buttons["squad.join"]
        XCTAssertTrue(join.waitForExistence(timeout: Self.wait), "你的小队 never appeared")
        XCTAssertEqual(app.textFields["squad.name"].value as? String, "Tracy 的小队")
        settle()
        keepScreenshot(named: "42-signup-squad-create")
        join.tap()
        let code = app.textFields["squad.code"]
        XCTAssertTrue(code.waitForExistence(timeout: Self.wait), "no invite code field")
        code.tap()
        code.typeText("k7q2m9xd")
        // The found squad is one combined element, which reads as text rather than a group.
        let found = app.descendants(matching: .any)["squad.found"]
        XCTAssertTrue(found.waitForExistence(timeout: Self.wait), "the squad wasn't found")
        settle()
        let squadDone = app.buttons["squad.done"]
        XCTAssertTrue(
            app.descendants(matching: .any)["squad.aiConsent"].exists, "no AI consent line under 加入小队")
        waitFor(squadDone, "isEnabled == true", "加入小队 stays off with a squad found")
        XCTAssertLessThanOrEqual(
            app.descendants(matching: .any)["squad.found"].frame.maxY, squadDone.frame.minY,
            "加入小队 covers the squad found")
        keepScreenshot(named: "43-signup-squad-join")
        squadDone.tap()
    }

    private func pickSports(in app: XCUIApplication) {
        let run = app.buttons["sports.run"]
        XCTAssertTrue(run.waitForExistence(timeout: Self.wait), "平时练什么？ never appeared")
        let next = app.buttons["sports.done"]
        XCTAssertFalse(next.isEnabled, "下一步 is on with nothing picked")
        run.tap()
        app.buttons["sports.climb"].tap()
        waitFor(next, "isEnabled == true", "下一步 stays off with sports picked")
        settle()
        keepScreenshot(named: "44-signup-sports")
        next.tap()
    }

    private func planTheWeek(in app: XCUIApplication) {
        let count = app.descendants(matching: .any)["week.count"]
        XCTAssertTrue(count.waitForExistence(timeout: Self.wait), "一周练几天？ never appeared")
        settle()
        keepScreenshot(named: "45-signup-week")
        // The whole poster and the day's choices show above the buttons, with no scrolling.
        let rest = app.buttons["week.choice.rest"]
        XCTAssertLessThanOrEqual(count.frame.maxY, rest.frame.minY, "the week's total is under the choices")
        XCTAssertLessThanOrEqual(rest.frame.maxY, app.buttons["week.done"].frame.minY, "上场 covers the choices")
        XCTAssertGreaterThanOrEqual(app.buttons["week.day.0"].frame.height, 38, "a day is as tall as the board's row")
        rest.tap()
        settle()
        keepScreenshot(named: "46-signup-week-changed")
        app.buttons["week.done"].tap()
    }

    /// Frames of 上场 as fast as the simulator takes them, for the MP4; the squad card has
    /// dropped in by four seconds, and home takes over at the end.
    private func watchTheEntrance(in app: XCUIApplication) {
        let entrance = app.descendants(matching: .any)["entrance"]
        XCTAssertTrue(entrance.waitForExistence(timeout: Self.wait), "上场 never started")
        let start = Date.now
        var frame = 0
        var checkedCard = false
        while Date.now.timeIntervalSince(start) < 7 {
            keepScreenshot(named: String(format: "47-signup-entrance-%02d", frame))
            frame += 1
            if !checkedCard, Date.now.timeIntervalSince(start) > 4 {
                XCTAssertTrue(
                    app.descendants(matching: .any)["entrance.card"].exists, "the squad card never dropped in")
                checkedCard = true
            }
        }
        XCTAssertTrue(app.buttons["tab.today"].waitForExistence(timeout: Self.wait), "home never took over")
        keepScreenshot(named: "48-signup-home")
    }

    /// Making a squad, skipping sports and the week, in English. Sign-up starts on a Monday, so
    /// no day is over yet and the default plan reads 5/7.
    func testStartingASquadInEnglish() {
        let app = launch(language: "en")
        let signIn = app.buttons["signup.signIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: Self.wait), "the open screen never appeared")
        XCTAssertEqual(signIn.label, "Continue with Apple")
        signIn.tap()
        let editorDone = app.buttons["editor.done"]
        XCTAssertTrue(editorDone.waitForExistence(timeout: Self.wait), "the editor never appeared")
        XCTAssertTrue(app.staticTexts["Create your Wildcard athlete"].exists, "step 1 has no title")
        let nickname = app.textFields["editor.nickname"]
        nickname.tap()
        nickname.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12))
        nickname.typeText("Sam\n")
        waitFor(editorDone, "isEnabled == true", "Done stays off with a nickname")
        editorDone.tap()

        let squadDone = app.buttons["squad.done"]
        XCTAssertTrue(squadDone.waitForExistence(timeout: Self.wait), "the squad step never appeared")
        XCTAssertEqual(app.textFields["squad.name"].value as? String, "Sam's squad")
        XCTAssertEqual(squadDone.label, "Start squad")
        keepScreenshot(named: "49-signup-squad-en")
        waitFor(squadDone, "isEnabled == true", "Start squad stays off with a name")
        squadDone.tap()

        let skip = app.buttons["sports.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: Self.wait), "the sports step never appeared")
        // Back on the squad step, the squad just made stays as it is and isn't made again.
        app.buttons["Back"].tap()
        XCTAssertTrue(squadDone.waitForExistence(timeout: Self.wait), "Back didn't return to the squad step")
        XCTAssertFalse(app.textFields["squad.name"].isEnabled, "the squad name can change after the squad was made")
        squadDone.tap()
        XCTAssertTrue(skip.waitForExistence(timeout: Self.wait), "the squad step didn't carry on to sports")
        skip.tap()
        let count = app.descendants(matching: .any)["week.count"]
        XCTAssertTrue(count.waitForExistence(timeout: Self.wait), "the week step never appeared")
        XCTAssertEqual(count.label, "Training 5/7 days a week")
        settle()
        keepScreenshot(named: "50-signup-week-en")
    }

    /// Whoever makes their squad picks where it trains on 这周在哪练？: five cartons, then the
    /// chosen one opens and they drop onto it at home, with no 上场.
    func testMakingASquadPicksItsScene() {
        let app = launch(language: "zh-Hans")
        let signIn = app.buttons["signup.signIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: Self.wait), "the open screen never appeared")
        signIn.tap()
        let editorDone = app.buttons["editor.done"]
        XCTAssertTrue(editorDone.waitForExistence(timeout: Self.wait), "角色和昵称 never appeared")
        let nickname = app.textFields["editor.nickname"]
        nickname.tap()
        nickname.typeText("Tracy\n")
        waitFor(editorDone, "isEnabled == true", "就这样 stays off with a nickname")
        editorDone.tap()
        let squadDone = app.buttons["squad.done"]
        XCTAssertTrue(squadDone.waitForExistence(timeout: Self.wait), "你的小队 never appeared")
        waitFor(squadDone, "isEnabled == true", "建小队 stays off with a name")
        squadDone.tap()
        let skipSports = app.buttons["sports.skip"]
        XCTAssertTrue(skipSports.waitForExistence(timeout: Self.wait), "平时练什么？ never appeared")
        skipSports.tap()
        let skipWeek = app.buttons["week.skip"]
        XCTAssertTrue(skipWeek.waitForExistence(timeout: Self.wait), "一周练几天？ never appeared")
        skipWeek.tap()

        let confirm = app.buttons["scene.done"]
        XCTAssertTrue(confirm.waitForExistence(timeout: Self.wait), "这周在哪练？ never appeared")
        XCTAssertTrue(app.staticTexts["这周在哪练？"].exists, "the scene step has no title")
        XCTAssertFalse(confirm.isEnabled, "就它了 is on before a carton is chosen")
        let tiles = ["track", "pool", "gym", "tennis", "climbing"].map { app.buttons["scenePick.\($0)"] }
        let screen = app.windows.firstMatch.frame
        for tile in tiles {
            XCTAssertTrue(tile.exists, "a scene is missing from the cartons")
            XCTAssertTrue(screen.contains(tile.frame), "a carton runs off the screen")
            XCTAssertLessThanOrEqual(tile.frame.maxY, confirm.frame.minY, "就它了 covers a carton")
        }
        XCTAssertEqual(tiles[1].label, "游泳池，还没开过")
        tiles[1].tap()
        waitFor(confirm, "isEnabled == true", "就它了 stays off with a carton chosen")
        settle()
        keepScreenshot(named: "51-signup-scene")
        confirm.tap()

        // The carton opens, then home takes over on the pool and the member drops onto it.
        let today = app.buttons["tab.today"]
        XCTAssertTrue(today.waitForExistence(timeout: Self.wait), "home never took over")
        // Frames a few times a second, to review the drop against the mockup.
        let start = Date()
        for frame in 0..<12 {
            keepScreenshot(
                named: String(
                    format: "52-signup-scene-dropping-%02d-%04dms", frame, Int(Date().timeIntervalSince(start) * 1000)))
        }
        XCTAssertFalse(app.descendants(matching: .any)["entrance"].exists, "上场 played for whoever made the squad")
        settle()
        keepScreenshot(named: "53-signup-scene-home")
    }

    private func launch(language: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(\(language))", "-AppleLocale", language, "-onboarding", "-uitest-monday",
        ]
        app.launch()
        // Close the app when the test ends, so the next launch never has to stop it.
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        return app
    }

    private func waitFor(_ element: XCUIElement, _ predicate: String, _ message: String) {
        let met = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [met], timeout: Self.wait), .completed, message)
    }

    /// Lets the characters build and their moves finish before a screenshot.
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
