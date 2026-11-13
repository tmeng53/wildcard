import XCTest

/// 入队申请 on the captain's 小队设置, on the in-memory squad with 小橘 waiting (`-squad-seat asked`).
/// Keeps screenshots for review.
@MainActor
final class SquadJoinRequestUITests: XCTestCase {
    /// 入队申请 tops the captain's 小队设置, the gear carrying a dot while anyone waits; 拒绝 takes
    /// the row away, and 入队需要审核 sits under 邀请队友.
    func testTheCaptainAnswersAJoinRequest() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-tab", "squad", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push",
            "-squad-seat", "asked",
        ]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        let gear = app.buttons["squad.preferences.open"]
        XCTAssertTrue(gear.waitForExistence(timeout: 30), "no 小队设置 on 小队's header")
        XCTAssertEqual(gear.value as? String, "有入队申请", "the gear has no dot while 小橘 waits")
        gear.tap()
        let requests = app.descendants(matching: .any)["squad.joinRequests"]
        XCTAssertTrue(requests.waitForExistence(timeout: 30), "no 入队申请 on the captain's 小队设置")
        let invite = app.buttons["squad.preferences.invite"]
        let approval = app.descendants(matching: .any)["squad.joinApproval"]
        XCTAssertTrue(approval.exists, "no 入队需要审核 on the captain's 小队设置")
        XCTAssertLessThan(requests.frame.minY, invite.frame.minY, "入队申请 isn't above 邀请队友")
        XCTAssertLessThan(invite.frame.minY, approval.frame.minY, "入队需要审核 isn't under 邀请队友")
        let decline = app.buttons["squad.joinRequest.decline"]
        for button in [decline, app.buttons["squad.joinRequest.approve"]] {
            XCTAssertTrue(button.isHittable, "拒绝 or 同意 can't be tapped")
            XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX, "拒绝 or 同意 runs off the screen")
        }
        settle()
        keepScreenshot(named: "92-squad-join-request")
        decline.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: requests)
        waitForExpectations(timeout: 30)
        settle()
        keepScreenshot(named: "93-squad-join-request-declined")
    }

    private func settle() {
        Thread.sleep(forTimeInterval: 1)
    }

    private func keepScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
