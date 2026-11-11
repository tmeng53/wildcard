#if os(iOS)
import CheckInDomain
import Contracts
import Foundation
import Testing

@testable import CheckInUI

@MainActor @Suite struct ComposeRestoreTests {
    private let squad = SquadID(UUID())
    private let tuesday = LocalDay(at: Date(timeIntervalSince1970: 1_792_515_600), in: .gmt)

    private func refused(_ draft: CheckInDraft, inFeed: Bool = true) throws -> PendingCheckIn {
        PendingCheckIn(
            id: CheckInID(UUID()), member: MemberID(UUID()), day: tuesday,
            createdAt: Timestamp(millisecondsSince1970: 0),
            audience: try Audience([squad]), inFeed: inFeed, draft: draft)
    }

    private func page() -> ComposeModel {
        ComposeModel(
            kind: .trained, purpose: .new(shareSquad: nil), postableDays: [tuesday.adding(days: -1), tuesday],
            suggestedActivity: .sport("run"), recentActivities: [], save: { _ in true }, close: {})
    }

    @Test func aRefusedTrainingComesBackWithEverythingItHad() throws {
        let photo = PreparedPhoto(id: UUID(), jpeg: Data([1]), size: nil)
        let post = try refused(
            .trained(.sport("swim"), try WorkoutMinutes(40), PostBody(photos: [photo], caption: "晨游")), inFeed: false)
        let model = page()
        model.restore(post)
        #expect(model.activity == .sport("swim"))
        #expect(model.minutes == (try WorkoutMinutes(40)))
        #expect(model.line == "晨游")
        #expect(model.photos == [.new(photo)])
        #expect(!model.inFeed)
        // Its day is today, so it posts for whatever day it is when sent.
        #expect(model.day == nil)
    }

    @Test func aBackfilledDayStaysWhileItCanStillBePosted() throws {
        let yesterday = tuesday.adding(days: -1)
        let post = PendingCheckIn(
            id: CheckInID(UUID()), member: MemberID(UUID()), day: yesterday, postedDay: tuesday,
            createdAt: Timestamp(millisecondsSince1970: 0), audience: try Audience([squad]),
            draft: .healthyMeal(PostBody(photos: [], caption: "沙拉")))
        let model = page()
        model.restore(post)
        #expect(model.day == yesterday)
        #expect(model.line == "沙拉")
    }

    @Test func aDayThatCantBePostedAnymoreFallsBackToToday() throws {
        let tooOld = tuesday.adding(days: -9)
        let post = PendingCheckIn(
            id: CheckInID(UUID()), member: MemberID(UUID()), day: tooOld, postedDay: tuesday,
            createdAt: Timestamp(millisecondsSince1970: 0), audience: try Audience([squad]),
            draft: .cheatMeal(PostBody(photos: [], caption: "")))
        let model = page()
        model.restore(post)
        #expect(model.day == nil)
    }
}
#endif
