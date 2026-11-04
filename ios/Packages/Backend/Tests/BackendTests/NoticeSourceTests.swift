import Contracts
import NotificationsDomain
import ScenePickDomain
import Testing

@testable import Backend

// 通知's adapter against the built API and local Supabase: a teammate's scene pick reaches the
// bell, and opening it marks it read.

@Test func aTeammatesScenePickIsInTheBellUntilItIsSeen() async throws {
    let stack = try LocalStack()
    let (captain, mate) = (try await stack.signedInMember(), try await stack.signedInMember())
    let squad = try await stack.squad(of: captain, mate)
    let week = try await APISquadSettingsService(api: captain.api).settings().scene.week
    try await APIScenePickService(api: captain.api, squad: squad, week: week).pick(.pool)

    let mates = APINoticeSource(api: mate.api)
    let page = try await mates.notices(before: nil)
    #expect(page.seenThrough == nil)
    #expect(page.next == nil)
    let moved = try #require(page.notices.first)
    #expect(page.notices.count == 1)
    #expect(moved.squad == squad)
    guard case .sceneMoved(let scene, let mover, _) = moved.subject else {
        Issue.record("not a scene move: \(moved.subject)")
        return
    }
    #expect(scene == "pool")
    #expect(mover == captain.id)

    try await mates.markSeen(through: moved.id)
    try await mates.markSeen(through: moved.id)
    #expect(try await mates.notices(before: nil).seenThrough == moved.id)

    // The picker isn't told their own pick.
    #expect(try await APINoticeSource(api: captain.api).notices(before: nil).notices.isEmpty)
}
