import APIContract
import Contracts
import Foundation
import OpenAPIRuntime
import Testing

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
        try Configuration.api.dateTranscoder.decode(try decoder.singleValueContainer().decode(String.self))
    }
    return try decoder.decode(type, from: Data(json.utf8))
}

private let myID = "22222222-2222-2222-2222-222222222222"
private let mate = "55555555-5555-5555-5555-555555555555"
private let squad = "33333333-3333-3333-3333-333333333333"

@Test func aSquadsTodayReads() throws {
    let wire = try decode(
        Components.Schemas.SquadToday.self,
        #"{"version":1,"squad":"\#(squad)","members":["#
            + #"{"member":"\#(mate)","catchphrase":"冲就完了","character":{"nickname":"阿杰","look":{"persona":"energetic","variants":{"body":"shiba"},"colors":{}}},"day":"2026-10-19","training":"trained","latestMeal":"cheatMeal","plannedRest":false,"firstCheckInAt":"2026-10-19T15:00:00.250Z"},"#
            + #"{"member":"\#(myID)","catchphrase":null,"day":"2026-10-19","training":"notCheckedIn","plannedRest":true}],"#
            + #""today":{"trained":1,"disclaimer":0,"resting":1,"everyoneTrained":true},"#
            + #""me":{"week":{"from":"2026-10-19","to":"2026-10-25","trainedDays":2,"plannedDays":5},"lifetimeTrainedDays":40},"#
            + #""squadWeek":{"trainedDays":14,"plannedDays":22}}"#)
    let today = try SquadToday(wire)
    let day = try LocalDay("2026-10-19")
    #expect(
        today
            == SquadToday(
                squad: SquadID(try #require(UUID(uuidString: squad))),
                members: [
                    SquadmateToday(
                        member: MemberID(try #require(UUID(uuidString: mate))), catchphrase: try Catchphrase("冲就完了"),
                        character: MemberCharacter(
                            nickname: try Nickname("阿杰"),
                            look: CharacterLook(
                                persona: "energetic", variants: ["body": "shiba"])),
                        day: day, training: .trained, latestMeal: .cheatMeal, plannedRest: false,
                        firstCheckInAt: Timestamp(millisecondsSince1970: 1_792_422_000_250)),
                    SquadmateToday(
                        member: MemberID(try #require(UUID(uuidString: myID))), catchphrase: nil, character: nil,
                        day: day, training: .notCheckedIn, latestMeal: nil, plannedRest: true, firstCheckInAt: nil),
                ],
                today: TodayCounts(trained: 1, disclaimer: 0, resting: 1, everyoneTrained: true),
                myWeek: MyWeek(
                    firstDay: day, lastDay: try LocalDay("2026-10-25"), week: WeekCount(trainedDays: 2, plannedDays: 5),
                    lifetimeTrainedDays: 40),
                squadWeek: WeekCount(trainedDays: 14, plannedDays: 22)))
}

@Test func aWeeklyPlanReads() throws {
    let wire = try decode(
        Components.Schemas.WeeklyPlan.self,
        #"{"version":1,"member":"\#(myID)","weekStart":"2026-10-19","source":"saved","fuelGoals":[],"days":["#
            + #"{"kind":"train","sport":"run"},{"kind":"train"},{"kind":"rest"},"#
            + #"{"kind":"train","sport":"custom","customSport":"飞盘"},{"kind":"train"},{"kind":"train"},{"kind":"rest"}]}"#
    )
    let plan = try WeeklyPlan(wire)
    #expect(plan.weekStart.description == "2026-10-19")
    #expect(
        plan.days == [
            .train(.sport(.run)), .train(nil), .rest, .train(.custom(try CustomSport("飞盘"))), .train(nil), .train(nil),
            .rest,
        ])
}

@Test func reactionsRead() throws {
    let wire = try decode(
        Components.Schemas.ReactionList.self,
        #"{"version":1,"reactions":[{"member":"\#(mate)","emoji":"😂","reactedAt":"2026-10-19T15:00:00.000Z"}]}"#)
    #expect(
        try wire.reactions.map(Reaction.init) == [
            Reaction(
                member: MemberID(try #require(UUID(uuidString: mate))), emoji: try Emoji("😂"),
                reactedAt: Timestamp(millisecondsSince1970: 1_792_422_000_000))
        ])
}

@Test func aSquadPostCarriesItsReactions() throws {
    let checkIn =
        #"{"version":1,"id":"66666666-6666-6666-6666-666666666666","member":"\#(myID)","day":"2026-10-19","#
        + #""createdAt":"2026-10-19T14:00:00.000Z","audience":["\#(squad)"],"kind":"disclaimer","#
        + #""disclaimer":{"text":"下雨了"}}"#
    let wire = try decode(
        Components.Schemas.SquadPostList.self,
        #"{"version":1,"posts":[{"checkIn":\#(checkIn),"#
            + #""reactions":[{"member":"\#(mate)","emoji":"🥹","reactedAt":"2026-10-19T15:00:00.000Z"}]}]}"#)
    let post = try #require(wire.posts.first)
    #expect(try CheckIn(post.checkIn).member == MemberID(try #require(UUID(uuidString: myID))))
    #expect(
        try post.reactions.map(Reaction.init) == [
            Reaction(
                member: MemberID(try #require(UUID(uuidString: mate))), emoji: try Emoji("🥹"),
                reactedAt: Timestamp(millisecondsSince1970: 1_792_422_000_000))
        ])
}

@Test func aReactionThatIsNotOneEmojiIsRefused() throws {
    let wire = try decode(
        Components.Schemas.ReactionList.self,
        #"{"version":1,"reactions":[{"member":"\#(mate)","emoji":"lol","reactedAt":"2026-10-19T15:00:00.000Z"}]}"#)
    #expect(throws: ContractsError.notAnEmoji("lol")) { try wire.reactions.map(Reaction.init) }
}

@Test func aReactionDraftCarriesItsEmoji() {
    #expect(Emoji.heart.draft == .init(version: ._1, emoji: "❤️"))
}
