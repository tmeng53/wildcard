import APIContract
import Contracts
import Foundation
import Testing

private func entry(action: String?, style: String = "banner", gifts: String = "[]") throws -> Notice? {
    let button =
        action.map {
            #", "action": {"label": {"zhHans": "去商店街看看", "en": "Take a look", "zhHant": "去商店街看看"}, "destination": "\#($0)"}"#
        } ?? ""
    let json = #"""
        {"id": 7, "kind": "broadcast", "at": "2026-11-20T08:00:00Z", "broadcast": "soon",
         "title": {"zhHans": "商店街上新了", "en": "New in the stores", "zhHant": "商店街上新了"},
         "style": "\#(style)", "gifts": \#(gifts)\#(button)}
        """#
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return Notice(try decoder.decode(Components.Schemas.NoticeEntry.self, from: Data(json.utf8)))
}

@Test func aBroadcastReadsWithItsWordsButtonAndGifts() throws {
    let notice = try #require(
        try entry(action: "stores", gifts: #"[{"kind": "piece", "id": "lap-bib"}, {"kind": "badge", "id": "x"}]"#))
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
    #expect(notice.destination == .stores)
}

@Test func aButtonOpensThePlaceItNames() throws {
    let post = "3a7e9c1b-2d4f-4b6a-8e0c-5f1d2b3c4a59"
    #expect(try entry(action: "store/deuce")?.destination == .store("deuce"))
    #expect(try entry(action: "post/\(post)")?.destination == .post(CheckInID(try #require(UUID(uuidString: post)))))
    #expect(try entry(action: "schedule")?.destination == .schedule)
    #expect(try entry(action: "me")?.destination == .profile)
}

@Test func aPlaceThisBuildDoesntKnowShowsNoButtonAndAnUnknownStyleIsABanner() throws {
    let notice = try #require(try entry(action: "arcade", style: "fireworks"))
    guard case .broadcast(let broadcast) = notice.subject else {
        Issue.record("not a broadcast")
        return
    }
    #expect(broadcast.action == nil)
    #expect(broadcast.style == .banner)
    #expect(notice.destination == nil)
    #expect(try entry(action: "post/nope")?.destination == nil)
    #expect(try entry(action: nil)?.destination == nil)
}
