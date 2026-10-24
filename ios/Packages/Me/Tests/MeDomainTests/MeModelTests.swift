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
}

struct CardNumberTests {
    private func overview(picked: Int?, place: Int?) throws -> MeOverview {
        var overview = sample
        overview.jerseyNumber = try picked.map { number throws(ContractsError) in try JerseyNumber(number) }
        overview.squadPlace = place
        return overview
    }

    @Test func isThePickElseThePlaceInTheSquad() throws {
        #expect(try overview(picked: 7, place: 3).cardNumber?.text == "07")
        #expect(try overview(picked: nil, place: 1).cardNumber?.text == "01")
        #expect(try overview(picked: nil, place: nil).cardNumber == nil)
    }

    @Test func numbersOnlyUpTo99() throws {
        #expect(try overview(picked: nil, place: 120).cardNumber?.text == "99")
        #expect(throws: ContractsError.jerseyNumberOutOfRange(100)) { try JerseyNumber(100) }
        #expect(throws: ContractsError.jerseyNumberOutOfRange(-1)) { try JerseyNumber(-1) }
    }
}

struct DeletionPhaseTests {
    @Test func takesATapOnlyWhileNothingIsRunning() {
        #expect(
            [DeletionPhase.reading, .deleting, .failed(.unavailable), .deleted].map(\.canConfirm) == [
                true, false, true, false,
            ])
    }
}
