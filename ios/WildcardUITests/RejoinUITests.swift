import XCTest

/// A member back in no squad (`-onboarding-rejoin`, with the in-memory squad).
@MainActor
final class RejoinUITests: XCTestCase {
    static let wait: TimeInterval = 30

    /// A member the captain removed (Tracy, 2026-11-11): told once, then 加入小队 alone, as the
    /// character they made, with no way back and no steps; joining goes 上场, then home.
    func testRejoiningAfterBeingRemoved() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-onboarding-rejoin", "-uitest-monday",
        ]
        // Home opens on the folded capsule, as these tests were written for.
        app.launchArguments.append("-uitest-card-folded")
        app.launch()
        // Close the app when the test ends, so the next launch never has to stop it.
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        let told = app.alerts.firstMatch
        XCTAssertTrue(told.waitForExistence(timeout: Self.wait), "the removal was never told")
        XCTAssertTrue(told.staticTexts["你已被移出 晨跑搭子"].exists, "the alert doesn't name the squad")
        keepScreenshot(named: "141-rejoin-removed")
        told.buttons["确认"].tap()
        let join = app.buttons["squad.join"]
        XCTAssertTrue(join.waitForExistence(timeout: Self.wait), "加入小队 never appeared")
        XCTAssertTrue(app.staticTexts["加入小队"].exists, "the page isn't titled 加入小队")
        XCTAssertFalse(app.buttons["返回"].exists, "the page has a way back")
        XCTAssertFalse(app.buttons["editor.done"].exists, "the character is made again")
        // The squad name follows the nickname kept from before.
        XCTAssertEqual(app.textFields["squad.name"].value as? String, "Tracy 的小队")
        XCTAssertFalse(
            app.descendants(matching: .any)["squad.aiConsent"].exists, "AI consent is asked again")
        join.tap()
        let code = app.textFields["squad.code"]
        XCTAssertTrue(code.waitForExistence(timeout: Self.wait), "no invite code field")
        code.tap()
        code.typeText("k7q2m9xd")
        let squadDone = app.buttons["squad.done"]
        waitFor(squadDone, "isEnabled == true", "加入小队 stays off with a squad found")
        settle()
        keepScreenshot(named: "142-rejoin-join")
        squadDone.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["entrance"].waitForExistence(timeout: Self.wait),
            "joining didn't go 上场")
        XCTAssertFalse(app.buttons["sports.done"].exists, "关于你 came again")
        XCTAssertTrue(app.buttons["today.checkin"].waitForExistence(timeout: Self.wait), "home never took over")
        keepScreenshot(named: "143-rejoin-home")
    }

    /// 入队申请 (Tracy, 2026-11-12): a squad whose captain lets members in shows only its name,
    /// heads and size; its button is 申请加入, with an optional 备注, and asking waits on 等队长同意
    /// with the captain and 撤回申请, which goes back to choose again.
    func testAskingTheCaptainWaitsForTheirOK() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-onboarding-rejoin", "-onboarding-ask",
            "-uitest-monday",
        ]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        let told = app.alerts.firstMatch
        XCTAssertTrue(told.waitForExistence(timeout: Self.wait), "the removal was never told")
        told.buttons["确认"].tap()
        let join = app.buttons["squad.join"]
        XCTAssertTrue(join.waitForExistence(timeout: Self.wait), "加入小队 never appeared")
        join.tap()
        let code = app.textFields["squad.code"]
        XCTAssertTrue(code.waitForExistence(timeout: Self.wait), "no invite code field")
        code.tap()
        code.typeText("k7q2m9xd")
        let note = app.textFields["squad.note"]
        XCTAssertTrue(note.waitForExistence(timeout: Self.wait), "no 备注 for a squad that asks its captain")
        let found = app.descendants(matching: .any)["squad.found"]
        XCTAssertTrue(found.exists, "the squad found isn't shown")
        XCTAssertFalse(found.label.contains("人均"), "the squad's goal shows before joining")
        note.tap()
        note.typeText("阿杰拉我来的")
        let squadDone = app.buttons["squad.done"]
        waitFor(squadDone, "isEnabled == true", "申请加入 stays off")
        XCTAssertTrue(app.buttons["申请加入"].exists, "the button isn't 申请加入")
        settle()
        keepScreenshot(named: "147-join-ask")
        squadDone.tap()
        let withdraw = app.buttons["waiting.withdraw"]
        XCTAssertTrue(withdraw.waitForExistence(timeout: Self.wait), "asking didn't wait on 等队长同意")
        XCTAssertTrue(app.staticTexts["等队长同意"].exists, "the page isn't titled 等队长同意")
        XCTAssertTrue(
            app.descendants(matching: .any)["waiting.captain"].exists, "the captain isn't shown")
        XCTAssertFalse(app.buttons["返回"].exists, "等队长同意 has a way back")
        XCTAssertFalse(app.descendants(matching: .any)["entrance"].exists, "went 上场 before the captain said")
        settle()
        keepScreenshot(named: "148-join-waiting")
        withdraw.tap()
        XCTAssertTrue(app.buttons["squad.done"].waitForExistence(timeout: Self.wait), "撤回申请 didn't go back")
        keepScreenshot(named: "149-join-withdrawn")
    }

    private func waitFor(_ element: XCUIElement, _ predicate: String, _ message: String) {
        let met = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [met], timeout: Self.wait), .completed, message)
    }

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
