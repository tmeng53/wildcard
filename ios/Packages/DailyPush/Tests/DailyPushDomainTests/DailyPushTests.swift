import Contracts
import FeedDomain
import Foundation
import Testing

@testable import DailyPushDomain

private let meID = "00000000-0000-4000-8000-000000000001"
private let miID = "00000000-0000-4000-8000-000000000002"
private let leo = "00000000-0000-4000-8000-000000000003"
private let squat = "10000000-0000-4000-8000-000000000001"
private let slip = "10000000-0000-4000-8000-000000000002"

/// A push as the server writes it: 小米's 练了 with Leo's 💪 and my 😂, then her 请假条.
private let event = """
    {
      "kind": "dailyProgress", "day": "2026-10-23", "squad": "s", "squadTrainedDays": 9,
      "squadPlannedDays": 16, "received": {"poke": 1},
      "today": {
        "members": [{"id": "\(meID)"}, {"id": "\(miID)", "name": "小米"}, {"id": "\(leo)", "name": "Leo"}],
        "posts": [
          {"id": "\(squat)", "by": 1, "kind": "trained", "sport": "strength",
           "at": "2026-10-23T21:42:00.000Z", "text": "深蹲加了 5 公斤", "reactions": [[0, "😂"], [2, "💪"]],
           "reactionCount": 7},
          {"id": "\(slip)", "by": 1, "kind": "disclaimer", "at": "2026-10-23T20:10:00.000Z",
           "text": "腿说今天它请假", "reactions": [], "reactionCount": 0}
        ],
        "more": 2, "pokedBy": [1]
      }
    }
    """

private let noon = Date(timeIntervalSince1970: 1_793_448_000)

private func id<Tag>(_ text: String) -> ID<Tag> { ID(UUID(uuidString: text) ?? UUID()) }

@Test func readsWhatThePushCarries() throws {
    let push = try DailyPush(event: Data(event.utf8))
    #expect(push.viewer == id(meID))
    #expect(push.squadWeek == WeekCount(trainedDays: 9, plannedDays: 16))
    #expect(push.pokedBy == [id(miID)])
    #expect(push.more == 2)
    #expect(push.name(of: id(miID)) == "小米")
    #expect(push.name(of: id(meID)) == nil)
    #expect(push.posts.map(\.entry) == [.trained(.sport(.strength)), .disclaimer])
    let squatPost = try #require(push.posts.first)
    #expect(squatPost.latest(4).map(\.member) == [id(meID), id(leo)])
    #expect(squatPost.latest(4).map(\.kind.text) == ["😂", "💪"])
    #expect(squatPost.reactionCount == 7)
    #expect(squatPost.text == "深蹲加了 5 公斤")
    #expect(!push.nobodyPosted)
}

@Test func postsThatDidNotFitStillMeanSomeonePosted() throws {
    let trimmed = event.replacingOccurrences(
        of: #"(?s)"posts": \[.*\],\s*"more": 2"#, with: #""posts": [], "more": 3"#, options: .regularExpression)
    let push = try DailyPush(event: Data(trimmed.utf8))
    #expect(push.posts.isEmpty)
    #expect(push.more == 3)
    #expect(!push.nobodyPosted)
    let quiet = try DailyPush(event: Data(trimmed.replacingOccurrences(of: #""more": 3"#, with: #""more": 0"#).utf8))
    #expect(quiet.nobodyPosted)
}

@Test func refusesAPushWithoutTheSquadDay() {
    #expect(throws: DailyPushError.unreadable) {
        try DailyPush(event: Data(#"{"kind": "dailyProgress", "squadTrainedDays": 1, "squadPlannedDays": 5}"#.utf8))
    }
    #expect(throws: DailyPushError.unreadable) {
        try DailyPush(event: Data(event.replacingOccurrences(of: "\"by\": 1", with: "\"by\": 9").utf8))
    }
}

private actor Sender: ReactionSender {
    var sent: [String?] = []
    var fails = false

    func failing() { fails = true }

    func setReaction(_ emoji: Emoji?, on checkIn: CheckInID) async throws(DailyPushError) {
        sent.append(emoji?.text)
        if fails { throw .notSent }
    }
}

@MainActor @Test func reactingShowsAtOnceAndTheSameEmojiTakesItBack() async throws {
    let sender = Sender()
    let store = DailyPushStore(push: try DailyPush(event: Data(event.utf8)), sender: sender, now: { noon })
    let move = try store.pick(try Emoji("❤️"), on: id(slip))
    #expect(move == MoveID("heart"))
    #expect(store.mine(on: id(slip))?.text == "❤️")
    #expect(store.post(id(slip))?.reactionCount == 1)
    await store.sending?.value

    // 😂 again on the squat takes mine back: no move, and the row loses my head.
    #expect(try store.pick(try Emoji("😂"), on: id(squat)) == nil)
    #expect(store.post(id(squat))?.latest(4).map(\.member) == [id(leo)])
    #expect(store.post(id(squat))?.reactionCount == 6)
    await store.sending?.value
    #expect(await sender.sent == ["❤️", nil])
}

@MainActor @Test func aReactionThatFailsIsPutBack() async throws {
    let sender = Sender()
    await sender.failing()
    let store = DailyPushStore(push: try DailyPush(event: Data(event.utf8)), sender: sender, now: { noon })
    try store.pick(try Emoji("🔥"), on: id(slip))
    #expect(store.mine(on: id(slip))?.text == "🔥")
    await store.sending?.value
    #expect(store.mine(on: id(slip)) == nil)
}

@MainActor @Test func nobodyReactsToAPostNotInThePush() async throws {
    let store = DailyPushStore(push: try DailyPush(event: Data(event.utf8)), sender: Sender(), now: { noon })
    #expect(throws: DailyPushError.unknownPost) { try store.pick(try Emoji("❤️"), on: id(meID)) }
}
