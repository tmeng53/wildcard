import APIContract
import Contracts
import Foundation
import Testing

private let coach = #""coach": {"id": "xiaohun", "name": "毛头", "look": "xiaohun"}"#

private func cards(_ stack: String, earlier: String = "") throws -> CoachPageCards {
    let json = #"{"version": 1, "stack": [\#(stack)], "earlier": [\#(earlier)]}"#
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return CoachPageCards(try decoder.decode(Components.Schemas.CoachCards.self, from: Data(json.utf8)))
}

@Test func aChallengeAndAGiftReadWithWhatTheyCarry() throws {
    let read = try cards(
        #"""
        {"kind": "challenge", "id": "41", \#(coach), "at": "2026-11-08T13:00:00Z", "day": "2026-11-08",
         "challenge": {"title": "拉伸", "amount": 5, "unit": "分钟", "line": "睡前拉一拉。", "answer": "accepted"}},
        {"kind": "gift", "id": "gift-sheeptowel", \#(coach), "at": "2026-11-08T13:00:01Z",
         "gift": {"pieceId": "gift-sheeptowel", "line": "别着凉。"}}
        """#)
    #expect(read.stack.map(\.kind) == [.challenge, .gift])
    let challenge = try #require(read.stack.first?.challenge)
    #expect(challenge == .init(title: "拉伸", amount: 5, unit: "分钟", line: "睡前拉一拉。", answer: .accepted))
    #expect(read.stack.first?.day == (try LocalDay("2026-11-08")))
    #expect(read.stack.first?.look == "xiaohun")
    #expect(read.stack.last?.gift == .init(piece: "gift-sheeptowel", line: "别着凉。"))
    #expect(read.stack.last?.gift?.isOpen == false)
}

@Test func aKindThisBuildDoesntKnowIsLeftOut() throws {
    // `reply` was a card once; the coach's lines to check-ins now show only under the posts.
    let read = try cards(
        #"{"kind": "reply", "id": "1", \#(coach), "at": "2026-11-08T13:00:00Z", "text": "…"}"#,
        earlier: #"{"kind": "note", "id": "7", \#(coach), "at": "2026-11-08T12:00:00Z", "text": "不错。"}"#
    )
    #expect(read.stack.isEmpty)
    #expect(read.earlier.map(\.kind) == [.note])
    #expect(read.earlier.first?.isSeen == false)
}

@Test func aPageOfEarlierReadsWhatWasSeenAndWhereTheNextStarts() throws {
    let json = #"""
        {"version": 1, "next": "1794150000000~note:7",
         "cards": [{"kind": "note", "id": "7", \#(coach), "at": "2026-11-08T12:00:00Z", "text": "不错。", "seen": true},
                   {"kind": "poem", "id": "8", \#(coach), "at": "2026-11-08T11:00:00Z", "seen": false}]}
        """#
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let page = CoachEarlierCards(try decoder.decode(Components.Schemas.EarlierCoachCards.self, from: Data(json.utf8)))
    #expect(page.cards.map(\.id) == ["7"])
    #expect(page.cards.first?.isSeen == true)
    #expect(page.next == "1794150000000~note:7")
}

@Test func todaysChallengeReadsWithWhoCompletedIt() throws {
    let json = #"""
        {"version": 1, "today": {"noteId": 41, "day": "2026-11-08",
         "challenge": {"title": "拉伸", "amount": 5, "unit": "分钟", "answer": "accepted",
                       "completedAt": "2026-11-08T20:00:00Z", "completedBy": "coach"}}}
        """#
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let wire = try decoder.decode(Components.Schemas.CoachDayChallenge.self, from: Data(json.utf8))
    let today = try #require(try DayChallenge(wire))
    #expect(today.note == "41")
    #expect(today.day == (try LocalDay("2026-11-08")))
    #expect(today.challenge == .init(title: "拉伸", amount: 5, unit: "分钟", answer: .accepted, completedBy: .coach))
    let none = try decoder.decode(
        Components.Schemas.CoachDayChallenge.self, from: Data(#"{"version": 1, "today": null}"#.utf8))
    #expect(try DayChallenge(none) == nil)
}
