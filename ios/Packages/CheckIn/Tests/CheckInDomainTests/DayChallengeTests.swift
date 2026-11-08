import CheckInDomain
import Contracts
import Foundation
import Testing

private func challenge(_ answer: CoachChallengeAnswer?, on day: LocalDay) -> DayChallenge {
    DayChallenge(
        note: "41", day: day,
        challenge: CoachPageCard.Challenge(title: "拉伸", amount: 5, unit: "分钟", answer: answer))
}

@MainActor @Test func onlyAnAcceptedChallengeOfTodayShowsOnMyWeek() async throws {
    let backend = ScriptedBackend(server: sampleHome())
    let today = store(backend)
    await today.load()
    let day = try #require(today.day)
    for (answer, shows) in [(CoachChallengeAnswer?.none, false), (.declined, false), (.accepted, true)] {
        await backend.set(challenge: challenge(answer, on: day))
        await today.loadCoach()
        #expect((today.acceptedChallenge != nil) == shows)
    }
    await backend.set(challenge: challenge(.accepted, on: day.adding(days: -1)))
    await today.loadCoach()
    #expect(today.acceptedChallenge == nil)
}

@MainActor @Test func iDidItMarksTheChallengeDoneAndPutsItBackWhenRefused() async throws {
    let backend = ScriptedBackend(server: sampleHome())
    let today = store(backend)
    await today.load()
    let day = try #require(today.day)
    await backend.set(challenge: challenge(.accepted, on: day))
    await today.loadCoach()
    await backend.set(completionFails: true)
    await today.completeChallenge()
    #expect(today.acceptedChallenge?.challenge.completedBy == nil)
    await backend.set(completionFails: false)
    await today.completeChallenge()
    #expect(today.acceptedChallenge?.challenge.completedBy == .member)
    #expect(!today.isCompletingChallenge)
}
