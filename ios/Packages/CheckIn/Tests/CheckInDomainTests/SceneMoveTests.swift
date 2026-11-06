import CheckInDomain
import Contracts
import DesignSystem
import Testing

private func squadScene(_ scene: SceneID, picked: SquadScene.Pick?) -> SquadScene {
    // swiftlint:disable:next force_try - a literal day.
    let monday = try! LocalDay(year: 2026, month: 11, day: 2)
    return SquadScene(
        week: monday, scene: scene, pickers: .crown([mate]), picked: picked,
        canPick: false, history: [])
}

@Test func aTeammatesPickIsToldWithWhoPickedIt() {
    let now = squadScene(.track, picked: .init(scene: .track, picker: mate))
    #expect(SceneMove(from: .gym, to: now, member: myID) == SceneMove(scene: .track, picker: mate))
}

@Test func myOwnPickTheSameSceneOrAFirstShowTellNothing() {
    let mine = squadScene(.track, picked: .init(scene: .track, picker: myID))
    let theirs = squadScene(.track, picked: .init(scene: .track, picker: mate))
    #expect(SceneMove(from: .gym, to: mine, member: myID) == nil)
    #expect(SceneMove(from: .track, to: theirs, member: myID) == nil)
    #expect(SceneMove(from: nil, to: theirs, member: myID) == nil)
}

@Test func aMoveWithoutThisWeeksPickOrAGonePickerNamesNobody() {
    let unpicked = squadScene(.pool, picked: nil)
    let gone = squadScene(.pool, picked: .init(scene: .pool, picker: nil))
    #expect(SceneMove(from: .gym, to: unpicked, member: myID) == SceneMove(scene: .pool, picker: nil))
    #expect(SceneMove(from: .gym, to: gone, member: myID) == SceneMove(scene: .pool, picker: nil))
}

@Test func aTakeoverSceneIsNobodysMove() {
    var holiday = squadScene(.ski, picked: .init(scene: .ski, picker: mate))
    holiday.takeover = "ski"
    #expect(SceneMove(from: .gym, to: holiday, member: myID) == nil)
}
