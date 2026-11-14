import APIContract
import Contracts
import Foundation
import Testing

private func read(_ card: String) throws -> CoachPageCards {
    let json = #"""
        {"version": 1, "stack": [{"kind": "message", "id": "equinox",
          "coach": {"id": "xiaohun", "name": "毛头", "look": "xiaohun"}, "at": "2026-11-14T13:00:00Z",
          \#(card)}], "earlier": []}
        """#
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return CoachPageCards(try decoder.decode(Components.Schemas.CoachCards.self, from: Data(json.utf8)))
}

private func words(_ zhHans: String) -> String {
    #"{"zhHans": "\#(zhHans)", "en": "\#(zhHans)", "zhHant": "\#(zhHans)"}"#
}

@Test func aMessageReadsItsCardsStageButtonsAndAnswers() throws {
    let member = "0a1b2c3d-0000-4000-8000-000000000001"
    let read = try read(
        #"""
        "message": {"cards": [
          {"path": "", "line": \#(words("周四去的 Equinox，打个分？")), "stage": {"cast": "members",
           "members": ["\#(member)", "not-an-id"], "move": "clap", "scene": "ski"}, "stars": true,
           "about": {"icon": "dumbbell", "name": \#(words("Equinox"))},
           "buttons": [{"id": "more", "label": \#(words("还有话说")), "style": "glow",
                        "tap": [{"next": "more"}, {"teleport": "x"}]}],
           "thanks": \#(words("收到。"))},
          {"path": "more", "line": \#(words("还想说什么？")), "stage": {"cast": "dance"}, "stars": false,
           "input": {}, "buttons": [{"id": "send", "label": \#(words("发送")), "style": "primary",
           "tap": [{"feedback": "idea"}, {"open": "feed"}, {"close": true}]}]}],
         "answered": [{"path": "", "stars": 4, "tap": "more"}]}
        """#)
    let message = try #require(read.stack.first?.message)
    #expect(read.stack.first?.kind == .message)
    let first = try #require(message.card(at: ""))
    #expect(
        first.stage
            == .init(cast: .members([MemberID(try #require(UUID(uuidString: member)))]), move: "clap", scene: "ski"))
    #expect(first.about?.name.simplifiedChinese == "Equinox")
    #expect(first.stars)
    // A style this build doesn't know is an outline; a step it doesn't know is left out.
    #expect(first.buttons.first?.style == .outline)
    #expect(first.buttons.first?.tap == [.next("more")])
    #expect(first.thanks?.english == "收到。")
    let more = try #require(message.card(at: "more"))
    // A cast this build doesn't know is the coach and the reader.
    #expect(more.stage.cast == .coachAndMe)
    #expect(more.input == CoachMessage.Input())
    #expect(more.buttons.first?.tap == [.feedback("idea"), .open("feed"), .close])
    #expect(message.answered[""] == .init(tap: "more", stars: 4))
    #expect(message.place == .card("more"))
}

@Test func aMessageCardWithoutItsMessageIsLeftOut() throws {
    #expect(try read(#""text": "…""#).stack.isEmpty)
}

@Test func anAnswerGoesAsOnePart() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let sent = String(decoding: try encoder.encode(CoachMessage.Part.stars(4).wire(on: "more")), as: UTF8.self)
    #expect(sent == #"{"path":"more","stars":4,"version":1}"#)
}
