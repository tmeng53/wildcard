#if os(iOS)
import Contracts

extension TodayModel {
    /// The member saved their character in 我's editor: they wear it on the scene at once, and
    /// once `save` is done the home is read again, so the server's look stands (the new one, or
    /// the old one back if the save failed) whatever a read already on its way brought.
    public func wear(_ character: MemberCharacter, save: @escaping @MainActor () async -> Void) async {
        store.wear(character)
        placeSquad()
        await save()
        await store.refresh()
        placeSquad()
    }
}
#endif
