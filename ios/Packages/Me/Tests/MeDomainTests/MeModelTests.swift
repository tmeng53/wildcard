import AvatarArt
import Contracts
import Foundation
import Testing

@testable import MeDomain

/// A member in memory that can be told to fail, and remembers what it was asked.
private actor FakeService: MeService {
    var current: MeOverview
    var failing: MeError?
    private(set) var deletedWith: DeletionConfirmation?
    private(set) var pushSaves: [Bool] = []
    /// While set, a delete waits until `release()`.
    private var holdsDeletes = false
    private var heldDelete: CheckedContinuation<Void, Never>?

    init(_ overview: MeOverview) { current = overview }

    func fail(with error: MeError?) { failing = error }

    func holdDeletes() { holdsDeletes = true }

    var isHoldingADelete: Bool { heldDelete != nil }

    func release() {
        heldDelete?.resume()
        heldDelete = nil
    }

    func overview() async throws(MeError) -> MeOverview {
        if let failing { throw failing }
        return current
    }

    func save(_ character: MeCharacter) async throws(MeError) {
        if let failing { throw failing }
        current.character = character
    }

    func save(jerseyNumber: JerseyNumber) async throws(MeError) {
        if let failing { throw failing }
        current.jerseyNumber = jerseyNumber
    }

    func setDailyPush(_ isOn: Bool) async throws(MeError) {
        pushSaves.append(isOn)
        if let failing { throw failing }
        current.dailyPushOn = isOn
    }

    private(set) var coachPushSaves: [Bool] = []
    func setCoachPush(_ isOn: Bool) async throws(MeError) {
        coachPushSaves.append(isOn)
        if let failing { throw failing }
        current.coachPushOn = isOn
    }

    func equip(_ title: String?) async throws(MeError) -> TitleBoard {
        if let failing { throw failing }
        current.board.worn = title ?? current.board.titles.first?.title
        return current.board
    }

    func claim(piece: String) async throws(MeError) {
        if let failing { throw failing }
        current.claimed.insert(piece)
    }

    func deleteAccount(_ confirmation: DeletionConfirmation) async throws(MeError) {
        if holdsDeletes { await withCheckedContinuation { heldDelete = $0 } }
        if let failing { throw failing }
        deletedWith = confirmation
    }
}

/// Counts sign-outs on this phone.
@MainActor private final class SignOuts {
    var count = 0
}

private let sample = MeOverview(
    character: MeCharacter(nickname: "小林", outfit: PlaceholderCharacter.lifter, persona: .energetic),
    joinedAt: Date(timeIntervalSince1970: 1_792_756_800),
    counts: LifetimeCounts(trainedDays: 128, healthyMeals: 46, cheatMeals: 12, disclaimers: 9),
    week: WeekCount(trainedDays: 3, plannedDays: 5), squadName: "周三不练腿俱乐部", dailyPushOn: true,
    squadPlace: 2)

private let shield = TitleBadge(shape: "shield", colour: "track", glyph: "sun.max.fill")
private let hexagon = TitleBadge(shape: "hexagon", colour: "gym", glyph: "snowflake")

/// Two titles: 早八战神 won last week, 冷面杀手 twice before.
private func board() throws -> TitleBoard {
    TitleBoard(
        titles: [
            BoardTitle(
                title: "早八战神", badge: shield,
                weeks: [BoardTitle.Week(weekStart: try LocalDay("2026-10-26"), speech: "天天七点")]),
            BoardTitle(
                title: "冷面杀手", badge: hexagon,
                weeks: [
                    BoardTitle.Week(weekStart: try LocalDay("2026-10-19"), speech: nil),
                    BoardTitle.Week(weekStart: try LocalDay("2026-10-12"), speech: "一句话不说", squadName: "早八跑团"),
                ]),
        ], worn: "早八战神")
}

/// A squadmate's card, read through the port.
private struct FakeCards: SquadmateCards {
    let result: Result<PlayerCardFace, MeError>

    func card(of member: MemberID, in squad: SquadID) async throws(MeError) -> PlayerCardFace {
        try result.get()
    }
}

@MainActor
struct MeModelTests {
    private func model(
        _ service: FakeService, signOuts: SignOuts = SignOuts(),
        confirm: @escaping @MainActor () async throws(MeError) -> DeletionConfirmation = {
            .apple(authorizationCode: "code-1")
        }
    ) -> MeModel {
        MeModel(service: service, confirm: confirm, signOut: { signOuts.count += 1 })
    }

    @Test func readsTheOverview() async {
        let page = model(FakeService(sample))
        #expect(page.load == .loading)
        await page.reload()
        #expect(page.load == .loaded(sample))
        #expect(page.dailyPushOn)
    }

    @Test func showsTheFailureOnlyWhenNothingIsOnScreen() async {
        let service = FakeService(sample)
        await service.fail(with: .unavailable)
        let page = model(service)
        await page.reload()
        #expect(page.load == .failed(.unavailable))

        await service.fail(with: nil)
        await page.reload()
        await service.fail(with: .unavailable)
        await page.reload()
        #expect(page.load == .loaded(sample))
    }

    @Test func savesTheSwitchAndFlipsItBackWhenSavingFails() async {
        let service = FakeService(sample)
        let page = model(service)
        await page.reload()

        await page.setDailyPush(false)
        #expect(!page.dailyPushOn)
        #expect(!page.saveFailed)

        await service.fail(with: .unavailable)
        await page.setDailyPush(true)
        #expect(!page.dailyPushOn)
        #expect(page.saveFailed)
        // Flipping to what it already is saves nothing.
        await page.setDailyPush(false)
        #expect(await service.pushSaves == [false, true])
    }

    @Test func savesTheCoachsSwitchApartFromTheDailyPush() async {
        let service = FakeService(sample)
        let page = model(service)
        await page.reload()
        await page.setCoachPush(false)
        #expect(!page.coachPushOn && page.dailyPushOn)
        #expect(await service.coachPushSaves == [false])
        #expect(await service.pushSaves.isEmpty)
        await service.fail(with: .unavailable)
        await page.setCoachPush(true)
        #expect(!page.coachPushOn && page.saveFailed)
    }

    @Test func showsTheEditedCharacterOnceSaved() async {
        let service = FakeService(sample)
        let page = model(service)
        await page.reload()
        let edited = MeCharacter(nickname: "林林", outfit: PlaceholderCharacter.lifter, persona: .shy)
        await page.save(edited)
        #expect(page.overview?.character == edited)
        #expect(!page.saveFailed)

        await service.fail(with: .rejected)
        let refused = MeCharacter(nickname: "x", outfit: PlaceholderCharacter.lifter, persona: .drama)
        await page.save(refused)
        #expect(page.overview?.character == edited)
        #expect(page.saveFailed)
    }

    @Test func savesThePickedNumberAndKeepsTheOldOneWhenSavingFails() async throws {
        let service = FakeService(sample)
        let page = model(service)
        await page.reload()
        // Before a pick, the card wears the member's place in their squad.
        #expect(page.overview?.cardNumber?.text == "02")

        await page.save(jerseyNumber: try JerseyNumber(0))
        #expect(page.overview?.cardNumber?.text == "00")
        #expect(await service.current.jerseyNumber == (try JerseyNumber(0)))

        await service.fail(with: .unavailable)
        await page.save(jerseyNumber: try JerseyNumber(99))
        #expect(page.overview?.cardNumber?.text == "00")
        #expect(page.saveFailed)
    }

    @Test func signsOutThroughTheApp() async {
        let signOuts = SignOuts()
        let page = model(FakeService(sample), signOuts: signOuts)
        await page.signOut()
        #expect(signOuts.count == 1)
    }

    @Test func deletesWithApplesCodeThenSignsOut() async {
        let service = FakeService(sample)
        let signOuts = SignOuts()
        let page = model(service, signOuts: signOuts)
        await page.reload()
        await page.deleteAccount()
        #expect(page.deletion == .deleted)
        #expect(await service.deletedWith == .apple(authorizationCode: "code-1"))
        #expect(signOuts.count == 1)
    }

    @Test func closingApplesSheetChangesNothing() async {
        let service = FakeService(sample)
        let signOuts = SignOuts()
        let page = model(service, signOuts: signOuts) { () throws(MeError) in throw .confirmationCanceled }
        await page.deleteAccount()
        #expect(page.deletion == .reading)
        #expect(await service.deletedWith == nil)
        #expect(signOuts.count == 0)
    }

    @Test func aFailedDeleteCanBeTriedAgain() async {
        let service = FakeService(sample)
        await service.fail(with: .unavailable)
        let signOuts = SignOuts()
        let page = model(service, signOuts: signOuts)
        await page.deleteAccount()
        #expect(page.deletion == .failed(.unavailable))
        #expect(page.deletion.canConfirm)
        #expect(signOuts.count == 0)

        await service.fail(with: nil)
        await page.deleteAccount()
        #expect(page.deletion == .deleted)
        #expect(signOuts.count == 1)

        page.openDeletion()
        #expect(page.deletion == .reading)
    }

    @Test func anEndedSessionSignsOut() async {
        let service = FakeService(sample)
        let signOuts = SignOuts()
        let page = model(service, signOuts: signOuts)
        await page.reload()
        await service.fail(with: .signedOut)
        await page.deleteAccount()
        #expect(page.deletion == .failed(.signedOut))
        #expect(signOuts.count == 1)
        await page.setDailyPush(false)
        #expect(signOuts.count == 2)
    }

    @Test func theDeletionPageClosesUnlessDeleting() async {
        let service = FakeService(sample)
        let page = model(service, signOuts: SignOuts())
        #expect(page.isDeletionOpen == false)
        page.openDeletion()
        #expect(page.isDeletionOpen)
        page.closeDeletion()
        #expect(page.isDeletionOpen == false)

        await service.holdDeletes()
        page.openDeletion()
        let deleting = Task { await page.deleteAccount() }
        while await !service.isHoldingADelete { await Task.yield() }
        #expect(page.deletion == .deleting)
        page.closeDeletion()
        #expect(page.isDeletionOpen, "the page closed while the account was being deleted")
        await service.release()
        await deleting.value
        #expect(page.deletion == .deleted)
    }

    @Test func aFailedSwitchKeepsACharacterSavedMeanwhile() async {
        let service = FakeService(sample)
        let page = model(service, signOuts: SignOuts())
        await page.reload()
        let edited = MeCharacter(nickname: "阿林", outfit: PlaceholderCharacter.lifter, persona: .shy)
        await page.save(edited)
        await service.fail(with: .unavailable)
        await page.setDailyPush(false)
        #expect(page.dailyPushOn)
        #expect(page.overview?.character.nickname == "阿林")
    }

    // MARK: 头衔徽章

    @Test func theBoardCountsEveryWinAndWearsItsWornTitle() throws {
        let board = try board()
        #expect(board.count == 3)
        #expect(board.wornTitle == WornTitle(title: "早八战神", badge: shield))
        #expect(board.titles[1].times == 2)
        #expect(board.titles[1].latestSpeech == "一句话不说")
        // The squad named is the one the shown award line was won in, not another squad's week.
        #expect(board.titles[1].latestSquadName == "早八跑团")
        #expect(board.titles[0].latestSquadName == nil)
        #expect(TitleBoard.empty.wornTitle == nil)
    }

    @Test func equippingWearsTheTitleAtOnce() async throws {
        var overview = sample
        overview.board = try board()
        let service = FakeService(overview)
        let page = model(service)
        await page.reload()
        await page.equip("冷面杀手")
        #expect(page.overview?.board.worn == "冷面杀手")
        #expect(page.overview?.card.board.wornTitle?.badge == hexagon)
        #expect(await service.current.board.worn == "冷面杀手")
        await page.equip(String?.none)
        #expect(page.overview?.board.worn == "早八战神")
        #expect(!page.saveFailed)
    }

    @Test func aFailedEquipPutsTheWornTitleBack() async throws {
        var overview = sample
        overview.board = try board()
        let service = FakeService(overview)
        let page = model(service)
        await page.reload()
        await service.fail(with: .unavailable)
        await page.equip("冷面杀手")
        #expect(page.overview?.board.worn == "早八战神")
        #expect(page.saveFailed)
    }

    @Test func claimingPutsAnUnlockedPieceInTheWardrobeAndAFailedOneTakesItOut() async {
        var overview = sample
        let when = Date(timeIntervalSince1970: 1_793_577_600)
        overview.unlocks = [
            Unlock(kind: .piece, id: "lap-bib", unlockedAt: when, sports: ["run"], checkIns: 5),
            Unlock(kind: .piece, id: "lap-singlet", unlockedAt: when, sports: ["run"], checkIns: 7),
            Unlock(kind: .store, id: "lap", unlockedAt: when, sports: ["run"], checkIns: 3),
        ]
        let service = FakeService(overview)
        let page = model(service)
        await page.reload()
        #expect(page.unclaimed == ["lap-bib", "lap-singlet"])

        #expect(await page.claim("lap-bib"))
        #expect(page.unclaimed == ["lap-singlet"])
        #expect(await service.current.claimed == ["lap-bib"])

        await service.fail(with: .unavailable)
        #expect(await !page.claim("lap-singlet"))
        #expect(page.unclaimed == ["lap-singlet"])
        #expect(page.saveFailed)
    }

    @Test func theCardCarriesTheOverview() throws {
        var overview = sample
        overview.board = try board()
        let card = overview.card
        #expect(card.number?.text == "02")
        #expect(card.squadName == "周三不练腿俱乐部")
        #expect(card.counts.trainedDays == 128)
        #expect(card.board.count == 3)
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
}
