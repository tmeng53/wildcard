#if os(iOS)
import Contracts

extension TodayModel {
    /// The member saved their character in 我's editor: they wear it on the scene at once, and
    /// if the save failed the home is read again, so the server's look comes back.
    public func wear(_ character: MemberCharacter, saved: @escaping @MainActor () async -> Bool) async {
        store.wear(character)
        placeSquad()
        guard await saved() == false else { return }
        await store.refresh()
        placeSquad()
    }
}
#endif
