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
        connectHealth(in: app)
        planTheWeek(in: app)
        watchTheEntrance(in: app)
    }

    private func makeCharacter(in app: XCUIApplication) {
        let editorDone = app.buttons["editor.done"]
        XCTAssertTrue(editorDone.waitForExistence(timeout: Self.wait), "角色和昵称 never appeared")
        XCTAssertTrue(app.staticTexts["创建你的外卡运动员"].exists, "step 1 has no title")
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "editor.steps").firstMatch.label, "第 1 步，共 5 步")
        let nickname = app.textFields["editor.nickname"]
        nickname.tap()
        nickname.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12))
        // Return puts the keyboard away: the editor doesn't make room for it, so it covers 确认.
        nickname.typeText("Tracy\n")
        waitFor(editorDone, "isEnabled == true", "确认 stays off with a nickname")
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
        XCTAssertTrue(found.label.contains("人均每周 3 天"), "the squad found doesn't say its goal: \(found.label)")
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
        XCTAssertTrue(count.waitForExistence(timeout: Self.wait), "我的每周计划 never appeared")
        settle()
        keepScreenshot(named: "45-signup-week")
        // The whole poster and the day's choices show above the buttons, with no scrolling.
        let rest = app.buttons["week.choice.rest"]
        XCTAssertLessThanOrEqual(count.frame.maxY, rest.frame.minY, "the week's total is under the choices")
        XCTAssertLessThanOrEqual(rest.frame.maxY, app.buttons["week.done"].frame.minY, "上场 covers the choices")
        XCTAssertGreaterThanOrEqual(app.buttons["week.day.0"].frame.height, 38, "a day is as tall as the board's row")
        XCTAssertTrue(app.staticTexts["我的每周计划"].exists, "step 4 isn't titled 我的每周计划")
        XCTAssertEqual(app.buttons["week.done"].label, "上场", "a joiner doesn't go 上场 from step 4")
        XCTAssertTrue(app.buttons["week.day.0"].isEnabled, "Monday can't change on the 每周模板")
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
        // 上场 shows the tab bar too, so home is its own 打卡.
        XCTAssertTrue(app.buttons["today.checkin"].waitForExistence(timeout: Self.wait), "home never took over")
        keepScreenshot(named: "48-signup-home")
    }

    /// Making a squad, skipping sports and the week, in English. With no sport picked the 每周模板
    /// trains the squad's 人均 3 天 with no sport named: 3/7.
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
        skipHealth(in: app)
        let count = app.descendants(matching: .any)["week.count"]
        XCTAssertTrue(count.waitForExistence(timeout: Self.wait), "the week step never appeared")
        XCTAssertEqual(count.label, "Training 3/7 days a week")
        settle()
        keepScreenshot(named: "50-signup-week-en")
    }

    /// Whoever makes their squad picks where it trains on 这周在哪练？: five cartons, then the
    /// chosen one opens and they drop onto it at home, with no 上场.
    func testMakingASquadPicksItsScene() {
        let app = launch(language: "zh-Hans")
        makeCharacter(named: "Tracy", in: app)
        let squadDone = app.buttons["squad.done"]
        XCTAssertTrue(squadDone.waitForExistence(timeout: Self.wait), "你的小队 never appeared")
        waitFor(squadDone, "isEnabled == true", "建小队 stays off with a name")
        // 小队目标 under the name: 3 to begin with, and the creator's pick carries to step 4.
        pickSquadGoal(4, in: app)
        squadDone.tap()
        let skipSports = app.buttons["sports.skip"]
        XCTAssertTrue(skipSports.waitForExistence(timeout: Self.wait), "平时练什么？ never appeared")
        skipSports.tap()
        skipHealth(in: app)
        let skipWeek = app.buttons["week.skip"]
        XCTAssertTrue(skipWeek.waitForExistence(timeout: Self.wait), "我的每周计划 never appeared")
        let goal = app.descendants(matching: .any)["week.squadGoal"]
        XCTAssertTrue(goal.label.contains("人均 4 天"), "step 4 doesn't show the goal picked: \(goal.label)")
        XCTAssertEqual(app.buttons["week.done"].label, "下一步", "whoever made the squad goes on to pick its scene")
        skipWeek.tap()

        let confirm = app.buttons["scene.done"]
        XCTAssertTrue(confirm.waitForExistence(timeout: Self.wait), "这周在哪练？ never appeared")
        XCTAssertTrue(app.staticTexts["这周在哪练？"].exists, "the scene step has no title")
        XCTAssertFalse(confirm.isEnabled, "确认 is on before a carton is chosen")
        let tiles = ["track", "pool", "gym", "tennis", "climbing"].map { app.buttons["scenePick.\($0)"] }
        let screen = app.windows.firstMatch.frame
        for tile in tiles {
            XCTAssertTrue(tile.exists, "a scene is missing from the cartons")
            XCTAssertTrue(screen.contains(tile.frame), "a carton runs off the screen")
            XCTAssertLessThanOrEqual(tile.frame.maxY, confirm.frame.minY, "确认 covers a carton")
        }
        XCTAssertEqual(tiles[1].label, "游泳池，还没开过")
        tiles[1].tap()
        waitFor(confirm, "isEnabled == true", "确认 stays off with a carton chosen")
        settle()
        keepScreenshot(named: "51-signup-scene")
        confirm.tap()

        // The carton opens, then home takes over on the pool and the member drops onto it.
        // Home's own 打卡, there as the drop starts; the tab bar only comes back after it.
        let today = app.buttons["today.checkin"]
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

    /// Signs in on the open screen and names the character on 角色和昵称.
    private func makeCharacter(named name: String, in app: XCUIApplication) {
        let signIn = app.buttons["signup.signIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: Self.wait), "the open screen never appeared")
        signIn.tap()
        let editorDone = app.buttons["editor.done"]
        XCTAssertTrue(editorDone.waitForExistence(timeout: Self.wait), "角色和昵称 never appeared")
        let nickname = app.textFields["editor.nickname"]
        nickname.tap()
        nickname.typeText("\(name)\n")
        waitFor(editorDone, "isEnabled == true", "确认 stays off with a nickname")
        editorDone.tap()
    }

    /// Checks 小队目标 starts at 3 under 小队名, then picks `days`.
    private func pickSquadGoal(_ days: Int, in app: XCUIApplication) {
        let three = app.buttons["squad.goal.pick.3"]
        XCTAssertTrue(three.exists, "no 小队目标 under 小队名")
        XCTAssertTrue(three.isSelected, "小队目标 doesn't start at 3")
        app.buttons["squad.goal.pick.\(days)"].tap()
        XCTAssertTrue(app.buttons["squad.goal.pick.\(days)"].isSelected, "picking \(days) didn't take")
        settle()
        keepScreenshot(named: "42b-signup-squad-goal")
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

extension SignUpUITests {
    /// Making a squad in Traditional Chinese, which reads in Taiwan's words, not converted ones.
    func testStartingASquadInTraditionalChinese() {
        let app = launch(language: "zh-Hant")
        let signIn = app.buttons["signup.signIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: Self.wait), "the open screen never appeared")
        XCTAssertEqual(signIn.label, "使用 Apple 繼續")
        XCTAssertTrue(app.links["使用條款"].exists, "the terms line has no link to the terms")
        XCTAssertTrue(app.links["隱私權政策"].exists, "the terms line has no link to the privacy policy")
        settle()
        keepScreenshot(named: "54-signup-open-zh-hant")
        signIn.tap()
        let editorDone = app.buttons["editor.done"]
        XCTAssertTrue(editorDone.waitForExistence(timeout: Self.wait), "the editor never appeared")
        let nickname = app.textFields["editor.nickname"]
        nickname.tap()
        nickname.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12))
        nickname.typeText("Tracy\n")
        waitFor(editorDone, "isEnabled == true", "就這樣 stays off with a nickname")
        settle()
        keepScreenshot(named: "55-signup-character-zh-hant")
        editorDone.tap()

        let squadDone = app.buttons["squad.done"]
        XCTAssertTrue(squadDone.waitForExistence(timeout: Self.wait), "the squad step never appeared")
        XCTAssertEqual(app.textFields["squad.name"].value as? String, "Tracy 的小隊")
        XCTAssertEqual(squadDone.label, "建立小隊")
        keepScreenshot(named: "56-signup-squad-zh-hant")
        waitFor(squadDone, "isEnabled == true", "建立小隊 stays off with a name")
        squadDone.tap()

        let skip = app.buttons["sports.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: Self.wait), "the sports step never appeared")
        settle()
        keepScreenshot(named: "57-signup-sports-zh-hant")
        skip.tap()
        skipHealth(in: app)
        let count = app.descendants(matching: .any)["week.count"]
        XCTAssertTrue(count.waitForExistence(timeout: Self.wait), "the week step never appeared")
        XCTAssertEqual(count.label, "每週訓練 3/7 天")
        settle()
        keepScreenshot(named: "58-signup-week-zh-hant")
    }
}

/// 连上 Apple 健康, step 4.
extension SignUpUITests {
    /// 连上 Apple 健康: the sample run, the Fitbit, WHOOP and Oura guide, then 连接, which the sample
    /// library allows, so the step says 已连接 and goes on with 下一步.
    private func connectHealth(in app: XCUIApplication) {
        let connect = app.buttons["health.connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: Self.wait), "连上 Apple 健康 never appeared")
        XCTAssertTrue(app.descendants(matching: .any)["health.sample"].exists, "no sample run on 连上 Apple 健康")
        let guide = app.buttons["health.guide"]
        XCTAssertLessThanOrEqual(guide.frame.maxY, connect.frame.minY, "连接 covers the guide's link")
        XCTAssertLessThanOrEqual(guide.frame.height, 60, "the guide's link wraps to a second line")
        settle()
        keepScreenshot(named: "44b-signup-health")
        guide.tap()
        let open = app.buttons["health.guide.open"]
        XCTAssertTrue(open.waitForExistence(timeout: Self.wait), "the guide never opened")
        XCTAssertEqual(open.label, "打开 Google Health")
        let third = app.descendants(matching: .any)["health.guide.step.3"]
        XCTAssertTrue(third.exists, "the guide has no third step")
        XCTAssertLessThanOrEqual(third.frame.maxY, open.frame.minY, "打开 covers the last step")
        settle()
        keepScreenshot(named: "44c-signup-health-guide-fitbit")
        app.segmentedControls["health.guide.wearable"].buttons["WHOOP"].tap()
        XCTAssertEqual(open.label, "打开 WHOOP")
        app.segmentedControls["health.guide.wearable"].buttons["Oura"].tap()
        XCTAssertEqual(open.label, "打开 Oura")
        settle()
        keepScreenshot(named: "44d-signup-health-guide-oura")
        app.buttons["health.guide.close"].tap()
        XCTAssertTrue(connect.waitForExistence(timeout: Self.wait), "closing the guide didn't come back")
        connect.tap()
        let done = app.buttons["health.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.wait), "连接 didn't say 已连接")
        XCTAssertTrue(app.descendants(matching: .any)["health.connected"].exists, "no 已连接 line")
        settle()
        keepScreenshot(named: "44e-signup-health-connected")
        done.tap()
    }

    /// 以后再说 on 连上 Apple 健康.
    private func skipHealth(in app: XCUIApplication) {
        let skip = app.buttons["health.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: Self.wait), "连上 Apple 健康 never appeared")
        skip.tap()
    }
}
