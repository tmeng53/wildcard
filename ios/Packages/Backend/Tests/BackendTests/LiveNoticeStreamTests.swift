import Contracts
import NotificationsDomain
import OpenAPIRuntime
import Testing

@testable import Backend

// The live bell's stream as the server writes it (`GET /me/events`): `ready`, heartbeats,
// notices, and an event this build doesn't know, which it skips.

actor Heard {
    var all: [LiveNotice] = []
    func add(_ heard: LiveNotice) { all.append(heard) }
}

@Test func theStreamIsReadyThenTellsEachNoticeAndShelfChangeAndSkipsWhatItDoesNotKnow() async throws {
    let stream = """
        event: ready
        data: {"version":1}
        retry: 3000

        : ping

        event: notice
        data: {"version":1,"notice":{"id":42,"kind":"unlocked","at":"2026-11-04T01:02:03.456Z","unlockKind":"store","item":"no-look"}}
        id: 42

        event: confetti
        data: {"version":1}

        event: shelf
        data: {"version":1}

        event: notice
        data: {"version":1,"notice":{"id":43,"kind":"somethingNew","at":"2026-11-04T01:02:04.000Z"}}
        id: 43


        """
    let heard = Heard()
    try await WildcardAPI.read(HTTPBody(stream)) { await heard.add($0) }

    let all = await heard.all
    #expect(all.count == 4)
    #expect(all.first == .ready)
    guard case .told(let notice?) = all.dropFirst().first else {
        Issue.record("no notice: \(all)")
        return
    }
    #expect(notice.id == NoticeID(rawValue: 42))
    #expect(notice.subject == .unlocked(.store, item: "no-look"))
    #expect(all.dropFirst(2).first == .shelfChanged)
    #expect(all.last == .told(nil))
}
