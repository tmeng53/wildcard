import Contracts
import Foundation
import Testing

@testable import MeDomain

/// A player's card in its pop-up: a squadmate's, read only, and the member's own, which wears titles.
@MainActor
struct SquadmateCardTests {
    func model(_ service: FakeService) -> MeModel {
        MeModel(service: service, confirm: { .signedInSession }, signOut: {})
    }

    @Test func aSquadmatesCardLoadsWithTheirSquadsName() async throws {
        let face = PlayerCardFace(
            character: sample.character, number: try JerseyNumber(7), squadName: nil, joinedAt: nil,
            counts: .zero, week: nil, board: try board())
        let member = MemberID(UUID())
        let squad = SquadID(UUID())
        let loaded = SquadmateCardModel(
            member: member, squad: squad, squadName: "毛头教队", cards: FakeCards(result: .success(face)))
        await loaded.reload()
        var named = face
        named.squadName = "毛头教队"
        #expect(loaded.load == .loaded(named))

        let failed = SquadmateCardModel(
            member: member, squad: squad, squadName: nil, cards: FakeCards(result: .failure(.unavailable)))
        await failed.reload()
        #expect(failed.load == .failed(.unavailable))
    }

    @Test func theMembersOwnCardWearsATitleAndMeShowsIt() async throws {
        var overview = sample
        overview.board = try board()
        let service = FakeService(overview)
        let page = model(service)
        let face = PlayerCardFace(
            character: sample.character, number: nil, squadName: "毛头教队", joinedAt: nil, counts: .zero,
            week: nil, board: try board())
        let card = SquadmateCardModel(
            member: MemberID(UUID()), squad: SquadID(UUID()), squadName: nil,
            cards: FakeCards(result: .success(face)), own: page)
        #expect(card.canEquip)
        await card.reload()
        await card.equip(.title("冷面杀手"))
        guard case .loaded(let worn) = card.load else { throw MeError.unavailable }
        #expect(worn.board.worn == "冷面杀手")
        #expect(await service.current.board.worn == "冷面杀手")
        // 我 read after it opens shows the same title.
        await page.reload()
        #expect(page.overview?.board.worn == "冷面杀手")

        await service.fail(with: .unavailable)
        await card.equip(.title("早八战神"))
        guard case .loaded(let kept) = card.load else { throw MeError.unavailable }
        #expect(kept.board.worn == "冷面杀手")
        #expect(page.saveFailed)
    }

    @Test func aSquadmatesCardWearsNothing() async throws {
        let service = FakeService(sample)
        let face = PlayerCardFace(
            character: sample.character, number: nil, squadName: nil, joinedAt: nil, counts: .zero, week: nil,
            board: try board())
        let card = SquadmateCardModel(
            member: MemberID(UUID()), squad: SquadID(UUID()), squadName: nil,
            cards: FakeCards(result: .success(face)))
        #expect(!card.canEquip)
        await card.reload()
        await card.equip(.title("冷面杀手"))
        #expect(card.load == .loaded(face))
        #expect(await service.current.board.worn == nil)
    }
}
