import XCTest

/// 入队申请 on the captain's 小队设置, on the in-memory squad with 小橘 waiting (`-squad-seat asked`).
/// Keeps screenshots for review.
@MainActor
final class SquadJoinRequestUITests: XCTestCase {
    /// 今天 tells the captain in a banner that stays until it is tapped, and the squad's name
    /// wears a dot; 查看 opens 小队设置 with 入队申请 on top, 拒绝 takes the row away, and
    /// 入队需要审核 sits under 邀请队友.
    func testTheCaptainAnswersAJoinRequest() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans", "-uitest-no-push", "-squad-seat", "asked",
            // Open, whatever an earlier test on this simulator left it as: folded, the squad's name isn't shown.
            "-today.cardCollapsed", "0",
        ]
        app.launch()
        addTeardownBlock { @MainActor in XCUIApplication().terminate() }
        let squadName = app.descendants(matching: .any)["squadcard.squad"]
        XCTAssertTrue(squadName.waitForExistence(timeout: 30), "no squad card on 今天")
        XCTAssertEqual(squadName.value as? String, "有新消息", "the squad's name has no dot while 小橘 waits")

        // The banner shows once on a phone: a run after one that showed it goes by the gear.
        let banner = app.descendants(matching: .any).matching(identifier: "notice.banner").firstMatch
        if banner.waitForExistence(timeout: 15) {
            XCTAssertTrue(banner.label.contains("小橘 申请加入小队"), "the banner says \(banner.label)")
            XCTAssertTrue(banner.label.contains("查看"), "the banner has no 查看: \(banner.label)")
            XCTAssertLessThanOrEqual(banner.frame.maxX, app.frame.maxX, "the banner runs off the screen")
            Thread.sleep(forTimeInterval: 0.6)
            keepScreenshot(named: "92-join-request-banner")
            banner.tap()
        } else {
            squadName.tap()
            let gear = app.buttons["squad.preferences.open"]
            XCTAssertTrue(gear.waitForExistence(timeout: 30), "no 小队设置 on 小队's header")
            XCTAssertEqual(gear.value as? String, "有入队申请", "the gear has no dot while 小橘 waits")
            gear.tap()
        }

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
        keepScreenshot(named: "93-squad-join-request")
        decline.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: requests)
        waitForExpectations(timeout: 30)
        settle()
        keepScreenshot(named: "94-squad-join-request-declined")
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
