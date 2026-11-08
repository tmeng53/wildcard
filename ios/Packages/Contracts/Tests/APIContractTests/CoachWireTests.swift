import APIContract
import Contracts
import Foundation
import Testing

private let squad = "3a7e9c1b-2d4f-4b6a-8e0c-5f1d2b3c4a59"
private let squadID = SquadID(UUID(uuidString: squad) ?? UUID())

private func activity(letter: String) throws -> CoachActivity {
    let json = #"""
        {"version": 1, "note": null, "replies": [], "answers": []\#(letter)}
        """#
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let wire = try decoder.decode(Components.Schemas.CoachActivity.self, from: Data(json.utf8))
    return try CoachActivity(wire, squad: squadID)
}

@Test func theActivityCarriesTheLetterTheCoachWasLeft() throws {
    let read = try activity(
        letter: #"""
            , "letter": {"id": 4, "from": {"id": "xiaohun", "name": "毛头", "look": "xiaohun"},
             "to": {"id": "papa", "name": "帕帕", "look": "papa"}, "day": "2026-11-08",
             "text": "这队交给你了。", "at": "2026-11-08T18:00:00Z"}
            """#)
    #expect(
        read.letter
            == CoachLetter(
                id: 4, squad: squadID, from: CoachSpeaker(id: "xiaohun", name: "毛头"),
                to: CoachSpeaker(id: "papa", name: "帕帕"), day: try LocalDay("2026-11-08"), text: "这队交给你了。"))
}

@Test func aLetterThisBuildCantReadIsLeftOutNotTheActivity() throws {
    let read = try activity(
        letter: #"""
            , "letter": {"id": 4, "from": {"id": "Not An Id", "name": "毛头", "look": "x"},
             "to": {"id": "papa", "name": "帕帕", "look": "papa"}, "day": "2026-11-08",
             "text": "这队交给你了。", "at": "2026-11-08T18:00:00Z"}
            """#)
    #expect(read.letter == nil)
    #expect(try activity(letter: "").letter == nil)
}
