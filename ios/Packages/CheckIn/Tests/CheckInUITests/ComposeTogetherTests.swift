#if os(iOS)
import CheckInDomain
import Contracts
import Foundation
import Testing

@testable import CheckInUI

@MainActor @Suite struct ComposeTogetherTests {
    private let squad = Squad(
        id: SquadID(UUID()), name: "周三不练腿", inviteCode: "K7M2QX9P", members: [], captain: MemberID(UUID()))
    private let mia = MemberID(UUID())
    private let jie = MemberID(UUID())

    private func page(mates: [MemberID] = []) -> ComposeModel {
        let day = LocalDay(at: Date(timeIntervalSince1970: 1_792_515_600), in: .gmt)
        let today = mates.map {
            SquadmateToday(
                member: $0, catchphrase: nil, character: nil, day: day, training: .notCheckedIn, latestMeal: nil,
                plannedRest: false, firstCheckInAt: nil)
        }
        return ComposeModel(
            kind: .trained, purpose: .new(shareSquad: squad), suggestedActivity: .sport("run"), recentActivities: [],
            together: { _, _, _ in TrainingTogether(mates: today, hints: []) }, save: { _ in true }, close: {})
    }

    private func hint(_ mate: MemberID, namedMe: Bool) throws -> TrainingTogether.Hint {
        TrainingTogether.Hint(
            mate: mate, activity: .sport("swim"), minutes: try WorkoutMinutes(45),
            startTime: try StartTime(hour: 7, minute: 0), namedMe: namedMe)
    }

    @Test func squadmatesPickedGoWithTheTrainingInTheOrderPicked() throws {
        let model = page()
        model.toggle(mate: mia)
        model.toggle(mate: jie)
        if case .trained(_, _, let body) = model.draft {
            #expect(body.trainedWith.members == [mia, jie])
        } else {
            Issue.record("a 训练")
        }
        model.toggle(mate: mia)
        #expect(model.trainedWith == [jie])
        #expect(model.hasChanges)
    }

    @Test func aPostKeptToMeNamesNoOne() {
        let model = page()
        model.toggle(mate: mia)
        model.isShared = false
        if case .trained(_, _, let body) = model.draft { #expect(body.trainedWith.isEmpty) }
        #expect(model.together == .none)
    }

    @Test func aHintThatNamedMeStartsMyTrainingFromTheirs() throws {
        let model = page()
        model.take(try hint(jie, namedMe: true))
        #expect(model.trainedWith == [jie])
        #expect(model.activity == .sport("swim"))
        #expect(model.minutes == (try WorkoutMinutes(45)))
        #expect(model.startTime == (try StartTime(hour: 7, minute: 0)))
        // Tapped again, the squadmate goes and what it filled stays.
        model.take(try hint(jie, namedMe: true))
        #expect(model.trainedWith.isEmpty)
        #expect(model.activity == .sport("swim"))
    }

    @Test func aHintThatDidntNameMeOnlyPicksTheSquadmate() throws {
        let model = page()
        model.take(try hint(mia, namedMe: false))
        #expect(model.trainedWith == [mia])
        #expect(model.activity == nil)
        #expect(model.minutes == nil)
    }

    @Test func aSquadmateWhoLeftIsNotPostedNorCounted() throws {
        let gone = MemberID(UUID())
        let model = page(mates: [mia, jie])
        model.trainedWith = [gone, mia]
        if case .trained(_, _, let body) = model.draft { #expect(body.trainedWith.members == [mia]) }
    }

    @Test func aHintPastTheLimitFillsNothing() throws {
        let mates = (0..<TrainedWith.limit).map { _ in MemberID(UUID()) }
        let model = page(mates: mates + [jie])
        for mate in mates { model.toggle(mate: mate) }
        model.take(try hint(jie, namedMe: true))
        #expect(!model.trainedWith.contains(jie))
        #expect(model.activity == nil)
    }
}
#endif
