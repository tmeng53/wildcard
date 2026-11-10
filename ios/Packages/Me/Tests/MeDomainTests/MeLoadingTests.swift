import Contracts
import Testing

@testable import MeDomain

// 网络开小差了 shows only when a read really failed: one the page cut short (the tab left, the app
// went to the background) leaves it waiting, and a try after a failure waits under the loader.

/// A server that can't be reached.
private struct Unreachable: MeService {
    func overview() async throws(MeError) -> MeOverview { throw .unavailable }
    func records() async throws(MeError) -> WildcardRecords { throw .unavailable }
    func save(_ character: MeCharacter) async throws(MeError) { throw .unavailable }
    func save(jerseyNumber: JerseyNumber) async throws(MeError) { throw .unavailable }
    func save(birthday: Birthday?) async throws(MeError) { throw .unavailable }
    func setDailyPush(_ isOn: Bool) async throws(MeError) { throw .unavailable }
    func setCoachPush(_ isOn: Bool) async throws(MeError) { throw .unavailable }
    func equip(_ wearable: Wearable?) async throws(MeError) -> TitleBoard { throw .unavailable }
    func claim(piece: String) async throws(MeError) { throw .unavailable }
    func deleteAccount(_ confirmation: DeletionConfirmation) async throws(MeError) { throw .unavailable }
}

@MainActor private func page() -> MeModel {
    MeModel(service: Unreachable(), confirm: { .apple(authorizationCode: "code-1") }, signOut: {})
}

/// Runs `reload` in a task cancelled before it starts, as when the page leaves mid-read.
@MainActor private func cutShort(_ reload: @escaping @MainActor () async -> Void) async {
    let task = Task { await reload() }
    task.cancel()
    await task.value
}

@MainActor @Test func aReadCutShortIsNotAFailure() async {
    let tab = page()
    await cutShort { await tab.reload() }
    #expect(tab.load == .loading)
}

@MainActor @Test func aTryAfterAFailureShowsTheLoaderAgain() async {
    let tab = page()
    await tab.reload()
    #expect(tab.load == .failed(.unavailable))
    await cutShort { await tab.reload() }
    #expect(tab.load == .loading)
}
