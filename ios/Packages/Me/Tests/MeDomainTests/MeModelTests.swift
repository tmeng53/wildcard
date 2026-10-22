import AvatarArt
import Testing

@testable import MeDomain

/// A member in memory that can be told to fail, and remembers what it was asked.
private actor FakeService: MeService {
    var current: MeOverview
    var failing: MeError?
    private(set) var deletedWith: DeletionConfirmation?
    private(set) var pushSaves: [Bool] = []

    init(_ overview: MeOverview) { current = overview }

    func fail(with error: MeError?) { failing = error }

    func overview() async throws(MeError) -> MeOverview {
        if let failing { throw failing }
        return current
    }

    func save(_ character: MeCharacter) async throws(MeError) {
        if let failing { throw failing }
        current.character = character
    }

    func setDailyPush(_ isOn: Bool) async throws(MeError) {
        pushSaves.append(isOn)
        if let failing { throw failing }
        current.dailyPushOn = isOn
    }

    func deleteAccount(_ confirmation: DeletionConfirmation) async throws(MeError) {
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
    counts: LifetimeCounts(trainedDays: 128, healthyMeals: 46, cheatMeals: 12, disclaimers: 9),
    squadName: "周三不练腿俱乐部", dailyPushOn: true)

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

    @Test func theDeletionPageClosesUnlessDeleting() async {
        let service = FakeService(sample)
        let page = model(service, signOuts: SignOuts())
        #expect(page.isDeletionOpen == false)
        page.openDeletion()
        #expect(page.isDeletionOpen)
        page.closeDeletion()
        #expect(page.isDeletionOpen == false)
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

struct DeletionPhaseTests {
    @Test func takesATapOnlyWhileNothingIsRunning() {
        #expect(
            [DeletionPhase.reading, .deleting, .failed(.unavailable), .deleted].map(\.canConfirm) == [
                true, false, true, false,
            ])
    }
}
