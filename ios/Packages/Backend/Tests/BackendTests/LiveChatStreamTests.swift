import ChatDomain
import Contracts
import Foundation
import OpenAPIRuntime
import Testing

@testable import Backend

// The chat's live events as the server writes them on `GET /me/events`: a new message with the
// one it replies to, a deletion, the coach's dots, and the notices it leaves to the bell.

private actor HeardChat {
    var all: [ChatLive] = []
    func add(_ heard: ChatLive) { all.append(heard) }
}

@Test func theChatStreamTellsMessagesDeletionsAndTheCoachTyping() async throws {
    let squad = "6f1c1d2e-0000-4000-8000-000000000001"
    let ana = "6f1c1d2e-0000-4000-8000-0000000000a1"
    let message = """
        {"version":1,"id":"6f1c1d2e-0000-4000-8000-0000000000m2","seq":7,"member":"\(ana)","kind":"text",\
        "text":"@小混 走","replyTo":"6f1c1d2e-0000-4000-8000-000000000011","mentions":[],"mentionsCoach":true,\
        "at":"2026-11-04T01:02:03.456Z","reactions":[{"member":"\(ana)","emoji":"🔥"}]}
        """.replacingOccurrences(of: "m2", with: "02")
    let quoted = """
        {"version":1,"id":"6f1c1d2e-0000-4000-8000-000000000011","seq":3,"coachId":"xiaohun","kind":"note",\
        "text":"今天练腿","mentions":[],"mentionsCoach":false,"at":"2026-11-04T00:00:00.000Z","reactions":[]}
        """
    let stream = """
        event: ready
        data: {"version":1}

        event: notice
        data: {"version":1,"notice":{"id":42,"kind":"unlocked","at":"2026-11-04T01:02:03.456Z","unlockKind":"store","item":"no-look"}}

        event: coachTyping
        data: {"version":1,"squadId":"\(squad)","coachId":"xiaohun","typing":true}

        event: chat
        data: {"version":1,"squadId":"\(squad)","message":\(message),"quoted":\(quoted)}

        event: chatDeleted
        data: {"version":1,"squadId":"\(squad)","messageId":"6f1c1d2e-0000-4000-8000-000000000011"}

        event: chat
        data: {"version":1,"squadId":"\(squad)","message":{"version":1}}


        """
    let heard = HeardChat()
    try await WildcardAPI.readChat(HTTPBody(stream)) { await heard.add($0) }

    let all = await heard.all
    #expect(all.count == 4)
    #expect(all.first == .ready)
    let squadID = try #require(UUID(uuidString: squad)).squad
    #expect(all.dropFirst().first == .coachTyping(squadID, "xiaohun", typing: true))
    guard case .message(let target, let said, let quote?) = all.dropFirst(2).first else {
        Issue.record("no message: \(all)")
        return
    }
    #expect(target == squadID)
    #expect(said.seq == 7)
    #expect(said.mentionsCoach)
    #expect(said.reactions.map(\.emoji.text) == ["🔥"])
    #expect(quote.kind == .note)
    #expect(quote.author == .coach("xiaohun"))
    #expect(said.replyTo == quote.id)
    #expect(all.last == .deleted(squadID, quote.id))
}

extension UUID {
    fileprivate var squad: SquadID { SquadID(self) }
}
