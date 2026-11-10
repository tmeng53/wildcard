import Contracts
import Foundation
import Testing

@testable import MeDomain

/// The badges the team gave: worn on the card instead of a title, and NEW until opened.
@MainActor
struct TeamBadgeTests {
    func model(_ service: FakeService) -> MeModel {
        MeModel(service: service, confirm: { .signedInSession }, signOut: {})
    }

    @Test func wearingATeamBadgeTakesTheTitleOffAndShowsItsNameOnATicket() async throws {
        var overview = sample
        overview.board = try board()
        overview.board.teamBadges = [ideaKing]
        let service = FakeService(overview)
        let page = model(service)
        await page.reload()
        await page.equip(.teamBadge("idea-king"))
        let worn = try #require(page.overview?.board)
        #expect(worn.worn == nil)
        #expect(worn.wears(.teamBadge("idea-king")))
        #expect(!worn.wears(.title("早八战神")))
        #expect(
            worn.wornTitle(in: ["en"])
                == WornTitle(
                    title: "Idea King",
                    badge: TitleBadge(shape: "ticket", colour: "idea-king", tone: "#F2B33D", glyph: "lightbulb.fill")))
        #expect(worn.wornTitle(in: ["zh-Hant-TW"])?.title == "點子王")
        #expect(await service.current.board.wornTeamBadge == "idea-king")
        // A title worn again takes the badge off.
        await page.equip(.title("冷面杀手"))
        #expect(page.overview?.board.wornTeamBadge == nil)
        #expect(page.overview?.board.wornTitle(in: ["zh-Hans"])?.title == "冷面杀手")
    }

    @Test func aBadgeIsNewUntilOpenedAndNewAgainWhenGotAgain() throws {
        var board = try board()
        board.teamBadges = [ideaKing]
        let now = Date(timeIntervalSince1970: 1_794_268_800)  // 2026-11-10T00:00:00Z
        let today = try LocalDay("2026-11-10")
        // A first look on a phone: the badge got yesterday is new; the titles, all older, aren't.
        let firstLook = BadgeNews.seenAtFirstLook(board, now: now, today: today)
        #expect(BadgeNews.unseen(on: board, seen: firstLook) == ["team.idea-king.1"])
        // Opened: seen.
        let seen = firstLook.union(["team.idea-king.1"])
        #expect(BadgeNews.unseen(on: board, seen: seen).isEmpty)
        // Got a second time: new again.
        board.teamBadges[0].times = 2
        #expect(BadgeNews.unseen(on: board, seen: seen) == ["team.idea-king.2"])
    }

    @Test func aTitleWonLastWeekIsNewAtTheFirstLook() throws {
        let board = TitleBoard(
            titles: [
                BoardTitle(
                    title: "早八战神", badge: shield, weeks: [.init(weekStart: try LocalDay("2026-11-02"), speech: nil)]),
                BoardTitle(
                    title: "冷面杀手", badge: hexagon, weeks: [.init(weekStart: try LocalDay("2026-10-19"), speech: nil)]),
            ], worn: nil)
        let seen = BadgeNews.seenAtFirstLook(
            board, now: Date(timeIntervalSince1970: 1_794_268_800), today: try LocalDay("2026-11-10"))
        #expect(BadgeNews.unseen(on: board, seen: seen) == ["title.早八战神.1"])
    }

    private var ideaKing: TeamBadge {
        TeamBadge(
            id: "idea-king",
            name: CatalogNames(simplifiedChinese: "点子王", english: "Idea King", traditionalChinese: "點子王"),
            glyph: "lightbulb.fill", tone: "#F2B33D", times: 1,
            latestAt: Date(timeIntervalSince1970: 1_794_268_800 - 86_400))
    }
}
