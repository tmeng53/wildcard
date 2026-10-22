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
            + #"{"member":"\#(mate)","catchphrase":"冲就完了","day":"2026-10-19","training":"trained","latestMeal":"cheatMeal","plannedRest":false,"firstCheckInAt":"2026-10-19T15:00:00.250Z"},"#
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
                        day: day, training: .trained, latestMeal: .cheatMeal, plannedRest: false,
                        firstCheckInAt: Timestamp(millisecondsSince1970: 1_792_422_000_250)),
                    SquadmateToday(
                        member: MemberID(try #require(UUID(uuidString: myID))), catchphrase: nil, day: day,
                        training: .notCheckedIn, latestMeal: nil, plannedRest: true, firstCheckInAt: nil),
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
        #"{"version":1,"member":"\#(myID)","weekStart":"2026-10-19","source":"saved","days":["#
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
        #"{"version":1,"reactions":[{"member":"\#(mate)","kind":"lol","reactedAt":"2026-10-19T15:00:00.000Z"}]}"#)
    #expect(
        try wire.reactions.map(Reaction.init) == [
            Reaction(
                member: MemberID(try #require(UUID(uuidString: mate))), kind: .lol,
                reactedAt: Timestamp(millisecondsSince1970: 1_792_422_000_000))
        ])
}

@Test func reactionKindsAreTheAPIs() {
    #expect(
        ReactionKind.allCases.map(\.rawValue) == Components.Schemas.ReactionDraft.KindPayload.allCases.map(\.rawValue))
    #expect(ReactionKind.allCases.map(\.draft.kind.rawValue) == ReactionKind.allCases.map(\.rawValue))
}
