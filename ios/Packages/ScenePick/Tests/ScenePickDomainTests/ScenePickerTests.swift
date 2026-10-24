import Contracts
import DesignSystem
import ScenePickDomain
import Testing

/// Saves picks in memory, failing with `failure` when set.
private actor FakeService: ScenePickService {
    private(set) var picks: [SceneTheme] = []
    private let failure: ScenePickError?

    init(failure: ScenePickError? = nil) {
        self.failure = failure
    }

    func pick(_ scene: SceneTheme) async throws(ScenePickError) {
        if let failure { throw failure }
        picks.append(scene)
    }
}

private let options = [
    SceneOption(scene: .track, lastTrained: .thisWeek), SceneOption(scene: .pool, lastTrained: .weeksAgo(5)),
    SceneOption(scene: .gym, lastTrained: .never), SceneOption(scene: .tennis, lastTrained: .never),
]

@MainActor
struct ScenePickerTests {
    @Test func tilesFromTheSquadsScenesAsTheAPIListsThem() {
        let history = [
            SceneHistory(scene: .track, weeksAgo: 0), SceneHistory(scene: .pool, weeksAgo: 5),
            SceneHistory(scene: .gym, weeksAgo: nil), SceneHistory(scene: .tennis, weeksAgo: 1),
        ]
        #expect(
            SceneOption.options(from: history) == [
                SceneOption(scene: .track, lastTrained: .thisWeek),
                SceneOption(scene: .pool, lastTrained: .weeksAgo(5)),
                SceneOption(scene: .gym, lastTrained: .never), SceneOption(scene: .tennis, lastTrained: .weeksAgo(1)),
            ])
    }

    @Test func aNewSquadSeesEverySceneInACarton() async {
        let picker = ScenePicker.newSquad(service: FakeService())
        #expect(picker.options.map(\.scene) == [.track, .pool, .gym, .tennis, .climbing])
        #expect(picker.options.allSatisfy { !$0.isOpened })
        picker.select(.climbing)
        #expect(await picker.confirm() == Unboxing(boxed: true))
    }

    @Test func aCartonPicksOnceAndPlaysTheBoxedReveal() async {
        let service = FakeService()
        let picker = ScenePicker(options: options, service: service)
        #expect(!picker.canConfirm && picker.selectionLastTrained == nil)
        picker.select(.pool)
        #expect(picker.selectionLastTrained == .weeksAgo(5))
        picker.select(.tennis)
        #expect(picker.selectionLastTrained == .never && picker.canConfirm)
        #expect(await picker.confirm() == Unboxing(boxed: true))
        #expect(picker.phase == .picked(.tennis))
        // Locked for the week: no other tile, no second pick.
        picker.select(.pool)
        #expect(picker.selection == .tennis && !picker.canConfirm)
        #expect(await picker.confirm() == nil)
        #expect(await service.picks == [.tennis])
    }

    @Test func aSceneTheSquadKnowsRevealsWithoutACarton() async {
        let picker = ScenePicker(options: options, service: FakeService())
        picker.select(.track)
        #expect(picker.selectionLastTrained == .thisWeek)
        #expect(await picker.confirm() == Unboxing(boxed: false))
        // A scene the picker doesn't offer can't be chosen.
        let other = ScenePicker(options: options, service: FakeService())
        other.select(.climbing)
        #expect(other.selection == nil)
    }

    @Test func aFailedSaveCanBeTriedAgainUnlessItIsRefused() async {
        let offline = ScenePicker(options: options, service: FakeService(failure: .unavailable))
        offline.select(.gym)
        #expect(await offline.confirm() == nil)
        #expect(offline.phase == .failed(.unavailable) && offline.canConfirm)

        let refused = ScenePicker(options: options, service: FakeService(failure: .notAllowed))
        refused.select(.gym)
        #expect(await refused.confirm() == nil)
        #expect(refused.phase == .failed(.notAllowed) && !refused.canConfirm)
    }
}
