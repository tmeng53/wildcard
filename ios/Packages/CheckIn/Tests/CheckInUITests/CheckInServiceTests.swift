import CheckInDomain
import Contracts
import Foundation
import Testing

@testable import CheckInUI

private func service() -> InMemoryCheckInService {
    InMemoryCheckInService(
        board: TodayBoard(
            squadName: "squad", scene: .track, weekNumber: 42, progress: SquadWeekProgress(done: 14, goal: 22),
            trainedToday: 3, myStatus: .notCheckedIn, lastActivity: .sport(.run)))
}

private let photo = PreparedPhoto(jpeg: Data([1]))

@Test func theFirstTrainingOfTheDayTicksTheSquadBarOnce() async throws {
    let squad = service()
    let first = try await squad.post(.trained(.sport(.yoga), PostBody(photos: [], caption: "")))
    #expect(first.progress == SquadWeekProgress(done: 15, goal: 22))
    #expect(first.trainedToday == 4)
    #expect(first.myStatus == .trained)
    #expect(first.lastActivity == .sport(.yoga))
    let second = try await squad.post(.trained(.sport(.run), PostBody(photos: [], caption: "")))
    #expect(second.progress == SquadWeekProgress(done: 15, goal: 22))
    #expect(second.trainedToday == 4)
}

@Test func mealsDontMoveTheBarAndADisclaimerIsOnceADayBeforeTraining() async throws {
    let squad = service()
    let afterMeal = try await squad.post(.cheatMeal(PostBody(photos: [photo], caption: "火锅")))
    #expect(afterMeal.progress == SquadWeekProgress(done: 14, goal: 22))
    let afterDisclaimer = try await squad.post(.disclaimer(try Disclaimer("加班到十点")))
    #expect(afterDisclaimer.myStatus == .disclaimer)
    #expect(afterDisclaimer.progress.done == 14)
    await #expect(throws: CheckInError.disclaimerAlreadyPosted) {
        try await squad.post(.disclaimer(try Disclaimer("又加班")))
    }
    _ = try await squad.post(.trained(.sport(.run), PostBody(photos: [], caption: "")))
    await #expect(throws: CheckInError.alreadyTrained) {
        try await squad.post(.disclaimer(try Disclaimer("算了")))
    }
}

@Test func aPostKeepsThreePhotosAndOneLineOfSixty() {
    let photos = (0..<4).map { PreparedPhoto(jpeg: Data([UInt8($0)])) }
    let body = PostBody(photos: photos, caption: "  练腿日\n腿还在  ")
    #expect(body.photos == Array(photos.prefix(3)))
    #expect(body.cover == photos[0])
    #expect(body.caption == "练腿日腿还在")
    #expect(PostBody(photos: [], caption: "   ").caption == nil)
    #expect(PostBody(photos: [], caption: String(repeating: "练", count: 70)).caption?.count == 60)
}

@Test func theDiceRollsDifferentLines() {
    var generator = SplitMix(seed: 7)
    let lines = DiceDisclaimerWriter.roll(3, using: &generator)
    #expect(lines.count == 3)
    #expect(Set(lines).count == 3)
    #expect(lines.allSatisfy { $0.count <= Disclaimer.maxLength })
}

/// A seeded generator, so the roll is the same every run.
private struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
