import Contracts
import Foundation
import Testing

struct CoachNoteTests {
    private let maotou = CoachSpeaker(id: "xiaohun", name: "毛头")

    @Test func aLineLastsItsDayOnTheSquadsClock() throws {
        let taipei = try #require(TimeZone(identifier: "Asia/Taipei"))
        let note = CoachNote(
            day: try LocalDay("2026-11-08"), text: "今天谁先动，谁就是队长", coach: maotou,
            writtenAt: Date(timeIntervalSince1970: 0), timeZone: taipei)
        // 2026-11-08 09:00 in Taipei is still the 7th in New York.
        let morning = try #require(ISO8601DateFormatter().date(from: "2026-11-08T01:00:00Z"))
        #expect(note.isCurrent(at: morning))
        // 2026-11-09 04:00 in Taipei: the next day there, though still the 8th in New York.
        let nextDay = try #require(ISO8601DateFormatter().date(from: "2026-11-08T20:00:00Z"))
        #expect(!note.isCurrent(at: nextDay))
    }

    @Test func withoutAZoneItKeepsNewYork() throws {
        let note = CoachNote(
            day: try LocalDay("2026-11-08"), text: "今天随缘，来了就算", coach: maotou, writtenAt: Date(timeIntervalSince1970: 0))
        #expect(note.timeZone.identifier == "America/New_York")
    }
}
