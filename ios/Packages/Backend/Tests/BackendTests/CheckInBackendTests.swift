import AccountDomain
import CheckInDomain
import Contracts
import Foundation
import Testing

@testable import Backend

// The home and 打卡's data layer, `TodayStore`, over the real adapters: the API client against
// the built API and local Supabase, the home copy and outbox in files on disk.

private func scratch() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "wildcard-tests-\(UUID().uuidString)")
}

@MainActor private func store(_ member: SignedInMember, directory: URL, api: WildcardAPI? = nil) -> TodayStore {
    TodayStore(
        backend: APICheckInBackend(api: api ?? member.api, directory: directory),
        outbox: DeviceOutbox(directory: directory),
        now: { Date() }, newID: { UUID() })
}

private func jpeg(_ byte: UInt8) -> PreparedPhoto {
    PreparedPhoto(id: UUID(), jpeg: Data([0xFF, 0xD8, 0xFF, byte] + (0..<2048).map { _ in UInt8.random(in: 0...255) }))
}

@MainActor @Test func theHomeLoadsTheSquadsTodayAndKeepsACopy() async throws {
    let stack = try LocalStack()
    let author = try await stack.signedInMember()
    let mate = try await stack.signedInMember()
    let squad = try await stack.squad(of: author, mate)
    let directory = scratch()
    let today = store(author, directory: directory)

    await today.load()
    #expect(today.phase == .current)
    let home = try #require(today.home)
    #expect(home.member == author.id)
    #expect(home.squad.id == squad)
    #expect(home.squad.members == [author.id, mate.id])
    #expect(Set(home.today.members.map(\.member)) == [author.id, mate.id])
    #expect(home.today.today.trained == 0)
    #expect(home.plan.days.count == 7)
    #expect(today.myStatus == .notCheckedIn)

    // The copy on disk is the same home, read back without the network.
    #expect(await APICheckInBackend(api: author.api, directory: directory).savedHome() == home)
}

@MainActor @Test func theHomeHasTheMembersOwnCheckInsForTheirWeek() async throws {
    // The member's own week comes from their check-ins wherever they posted them: one posted to
    // a second squad shows up on the home of the first, which the squad's list alone would miss.
    let stack = try LocalStack()
    let author = try await stack.signedInMember()
    let shown = try await stack.squad(of: author)
    let other = try await stack.squad(of: author)
    let directory = scratch()
    let today = store(author, directory: directory)
    await today.load()
    #expect(today.home?.squad.id == shown)
    let day = try #require(today.day)
    let elsewhere = CheckIn(
        id: CheckInID(UUID()), member: author.id, day: day, createdAt: Timestamp(Date()),
        audience: try Audience([other]), entry: .healthyMeal(Meal(caption: try Caption("沙拉"))))
    _ = try await author.api.save(elsewhere)

    await today.load()
    #expect(today.home?.checkIns.map(\.id) == [elsewhere.id])
    // Kept on the device too.
    #expect(
        await APICheckInBackend(api: author.api, directory: directory).savedHome()?.checkIns.map(\.id) == [elsewhere.id]
    )
}

@MainActor @Test func aMemberInNoSquadHasNoHome() async throws {
    let stack = try LocalStack()
    let loner = try await stack.signedInMember()
    let today = store(loner, directory: scratch())
    await today.load()
    #expect(today.phase == .noSquad)
}

@MainActor @Test func aTrainingWithPhotosPostsCountsAndTheSquadSeesIt() async throws {
    let stack = try LocalStack()
    let author = try await stack.signedInMember()
    let mate = try await stack.signedInMember()
    _ = try await stack.squad(of: author, mate)
    let today = store(author, directory: scratch())
    await today.load()
    let before = try #require(today.home?.today.squadWeek.trainedDays)

    let photos = [jpeg(1), jpeg(2)]
    let outcome = try await today.post(.trained(.sport("climb"), PostBody(photos: photos, caption: "抱石 V3")))
    guard case .posted(let saved) = outcome else {
        Issue.record("expected posted, got \(outcome)")
        return
    }
    #expect(today.myStatus == .trained)
    #expect(today.home?.today.squadWeek.trainedDays == before + 1)

    // What the store counted on its own is what the server counts.
    await today.refresh()
    #expect(today.home?.today.squadWeek.trainedDays == before + 1)
    #expect(today.home?.mine?.training == .trained)

    let mates = store(mate, directory: scratch())
    await mates.load()
    let seen = try #require(mates.home?.todaysCheckIns(of: author.id).first)
    #expect(seen.id == saved.id)
    guard case .trained(let training) = seen.entry else {
        Issue.record("expected a 练了")
        return
    }
    #expect(training.photos?.all.count == 2)
    #expect(training.caption?.text == "抱石 V3")
    #expect(mates.home?.today.today.trained == 1)
}

@MainActor @Test func aPostMadeOfflineGoesOutOnceAfterTheAppReopens() async throws {
    let stack = try LocalStack()
    let author = try await stack.signedInMember()
    let mate = try await stack.signedInMember()
    let squad = try await stack.squad(of: author, mate)
    let directory = scratch()
    let online = store(author, directory: directory)
    await online.load()

    // The same member and home copy, with the API out of reach.
    let unreachable = try #require(URL(string: "http://127.0.0.1:9"))
    let offline = store(author, directory: directory, api: WildcardAPI(url: unreachable, account: author.account))
    await offline.load()
    #expect(offline.phase == .offline)
    #expect(offline.home?.member == author.id)
    let outcome = try await offline.post(.cheatMeal(PostBody(photos: [jpeg(3)], caption: "火锅")))
    #expect(outcome == .queued)
    #expect(offline.home?.mine?.latestMeal == .cheatMeal)

    // Reopened with the network back: the outbox on disk sends it, photo and all.
    let reopened = store(author, directory: directory)
    await reopened.load()
    #expect(reopened.pending.isEmpty)
    let pendingID = try #require(offline.pending.first?.id)
    let day = try #require(reopened.day)
    let seen = try await mate.api.checkIns(of: squad, from: day.adding(days: -1), through: day.adding(days: 1))
    #expect(seen.map(\.id) == [pendingID])
    guard case .cheatMeal(let meal) = seen.first?.entry else {
        Issue.record("expected a 坦白放纵餐")
        return
    }
    #expect(meal.photos?.all.count == 1)

    // Sending it again saves nothing new.
    await offline.sendPending()
    #expect(try await mate.api.checkIns(of: squad, from: day.adding(days: -1), through: day.adding(days: 1)).count == 1)
}

@MainActor @Test func aSecondDisclaimerIsRefusedEvenFromAnotherPhone() async throws {
    let stack = try LocalStack()
    let author = try await stack.signedInMember()
    _ = try await stack.squad(of: author)
    let phone = store(author, directory: scratch())
    let tablet = store(author, directory: scratch())
    await phone.load()
    await tablet.load()

    try await phone.post(.disclaimer(try Disclaimer("加班到十点")))
    await #expect(throws: CheckInError.disclaimerAlreadyPosted) {
        try await tablet.post(.disclaimer(try Disclaimer("又加班")))
    }
    #expect(tablet.pending.isEmpty)
}

@MainActor @Test func aTeammateReactsAndTheAuthorSeesIt() async throws {
    let stack = try LocalStack()
    let author = try await stack.signedInMember()
    let mate = try await stack.signedInMember()
    _ = try await stack.squad(of: author, mate)
    let authors = store(author, directory: scratch())
    await authors.load()
    guard case .posted(let saved) = try await authors.post(.trained(.sport("run"), PostBody(photos: [], caption: "")))
    else {
        Issue.record("expected posted")
        return
    }

    let mates = store(mate, directory: scratch())
    await mates.load()
    try await mates.react(.heart, to: saved.id)
    try await mates.react(try Emoji("😂"), to: saved.id)

    try await authors.loadReactions(to: saved.id)
    #expect(authors.reactions[saved.id]?.map(\.member) == [mate.id])
    #expect(authors.reactions[saved.id]?.map(\.emoji) == [try Emoji("😂")])
    #expect(authors.myReaction(on: saved.id) == nil)

    try await mates.removeReaction(from: saved.id)
    try await authors.loadReactions(to: saved.id)
    #expect(authors.reactions[saved.id] == [])
}

/// Stands in for the dice, so the test sees when it answered.
private struct Dice: DisclaimerWriter {
    func suggestions(for reason: String, style: DisclaimerStyle) async -> DisclaimerSuggestions {
        .drafts(["dice"])
    }
}

@Test func withoutTheAIWriterTheDiceAnswer() async throws {
    let stack = try LocalStack()
    let author = try await stack.signedInMember()
    try await author.api.agreeToAI(copyVersion: 1)
    // The local API runs without ANTHROPIC_API_KEY, so it answers 503.
    await #expect(throws: APIError.unavailable) {
        try await author.api.disclaimerDrafts(reason: "早上没起来", style: .funny)
    }
    let writer = APIDisclaimerWriter(api: author.api, fallback: Dice())
    #expect(await writer.suggestions(for: "早上没起来", style: .funny) == .drafts(["dice"]))
}
