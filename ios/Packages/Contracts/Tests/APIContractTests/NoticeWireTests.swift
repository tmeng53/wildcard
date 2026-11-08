import APIContract
import Contracts
import Foundation
import Testing

private func entry(
    action: String?, style: String = "banner", gifts: String = "[]", icon: String = "null"
) throws -> Notice? {
    let button =
        action.map {
            #", "action": {"label": {"zhHans": "去商店街看看", "en": "Take a look", "zhHant": "去商店街看看"}, "destination": "\#($0)"}"#
        } ?? ""
    let json = #"""
        {"id": 7, "kind": "broadcast", "at": "2026-11-20T08:00:00Z", "broadcast": "soon",
         "title": {"zhHans": "商店街上新了", "en": "New in the stores", "zhHant": "商店街上新了"},
         "style": "\#(style)", "gifts": \#(gifts), "icon": \#(icon)\#(button)}
        """#
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return Notice(try decoder.decode(Components.Schemas.NoticeEntry.self, from: Data(json.utf8)))
}

@Test func aBroadcastReadsWithItsWordsButtonAndGifts() throws {
    let notice = try #require(
        try entry(
            action: "stores", gifts: #"[{"kind": "piece", "id": "lap-bib"}, {"kind": "badge", "id": "x"}]"#,
            icon: #"{"kind": "store", "id": "powder"}"#))
    guard case .broadcast(let broadcast) = notice.subject else {
        Issue.record("not a broadcast")
        return
    }
    #expect(broadcast.id == "soon")
    #expect(broadcast.title.localized(in: ["en"]) == "New in the stores")
    #expect(broadcast.body == nil)
    #expect(broadcast.action?.label.localized(in: ["zh-Hans"]) == "去商店街看看")
    #expect(broadcast.style == .banner)
    // A kind this build doesn't know is left out.
    #expect(broadcast.gifts == [Broadcast.Gift(kind: .piece, id: "lap-bib")])
    #expect(broadcast.icon == Broadcast.Gift(kind: .store, id: "powder"))
    #expect(notice.destination == .stores)
}

@Test func aButtonOpensThePlaceItNames() throws {
    let post = "3a7e9c1b-2d4f-4b6a-8e0c-5f1d2b3c4a59"
    #expect(try entry(action: "store/deuce")?.destination == .store("deuce"))
    #expect(try entry(action: "post/\(post)")?.destination == .post(CheckInID(try #require(UUID(uuidString: post)))))
    #expect(try entry(action: "schedule")?.destination == .schedule)
    #expect(try entry(action: "me")?.destination == .profile)
    #expect(try entry(action: "notices")?.destination == .notices)
    #expect(try entry(action: "coaches")?.destination == .coaches)
}

@Test func aPlaceThisBuildDoesntKnowShowsNoButtonAndAnUnknownStyleIsABanner() throws {
    let notice = try #require(try entry(action: "arcade", style: "fireworks"))
    guard case .broadcast(let broadcast) = notice.subject else {
        Issue.record("not a broadcast")
        return
    }
    #expect(broadcast.action == nil)
    #expect(broadcast.style == .banner)
    #expect(broadcast.icon == nil)
    #expect(notice.destination == nil)
    #expect(try entry(action: "post/nope")?.destination == nil)
    #expect(try entry(action: nil)?.destination == nil)
}

@Test func aGoalSuggestionReadsAndOpensTheSquad() throws {
    let json = #"""
        {"id": 9, "kind": "goalSuggestion", "at": "2026-11-23T01:00:00Z",
         "squadId": "3a7e9c1b-2d4f-4b6a-8e0c-5f1d2b3c4a59", "weeks": 3, "daysPerMember": 4}
        """#
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let wire = try decoder.decode(Components.Schemas.NoticeEntry.self, from: Data(json.utf8))
    let notice = try #require(Notice(wire))
    #expect(notice.subject == .goalSuggestion(GoalSuggestion(weeks: 3, daysPerMember: 4)))
    #expect(notice.destination == .squad)
    // Without the goal it suggests, this build can't show it.
    let partial = #"{"id": 9, "kind": "goalSuggestion", "at": "2026-11-23T01:00:00Z", "weeks": 3}"#
    #expect(Notice(try decoder.decode(Components.Schemas.NoticeEntry.self, from: Data(partial.utf8))) == nil)
}

@Test func aCoachLetterReadsAndOpensTheLetterAgain() throws {
    let squad = "3a7e9c1b-2d4f-4b6a-8e0c-5f1d2b3c4a59"
    let json = #"""
        {"id": 12, "kind": "coachLetter", "at": "2026-11-08T18:00:00Z", "squadId": "\#(squad)",
         "letter": 4, "coach": "xiaohun", "coachName": "毛头", "toCoach": "papa", "toCoachName": "帕帕",
         "day": "2026-11-08", "text": "这队交给你了，我先撤。\n小美周三去游泳。"}
        """#
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let notice = try #require(Notice(try decoder.decode(Components.Schemas.NoticeEntry.self, from: Data(json.utf8))))
    let letter = CoachLetter(
        id: 4, squad: SquadID(try #require(UUID(uuidString: squad))), from: CoachSpeaker(id: "xiaohun", name: "毛头"),
        to: CoachSpeaker(id: "papa", name: "帕帕"), day: try LocalDay("2026-11-08"),
        text: "这队交给你了，我先撤。\n小美周三去游泳。")
    #expect(notice.subject == .coachLetter(letter))
    #expect(notice.destination == .coachLetter(letter))
    #expect(letter.lines == ["这队交给你了，我先撤。", "小美周三去游泳。"])
    // Without whom it is to, this build can't show it.
    let partial = json.replacingOccurrences(of: #""toCoach": "papa", "#, with: "")
    #expect(Notice(try decoder.decode(Components.Schemas.NoticeEntry.self, from: Data(partial.utf8))) == nil)
}
