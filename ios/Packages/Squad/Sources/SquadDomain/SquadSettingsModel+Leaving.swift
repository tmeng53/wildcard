import Contracts

// 退出小队 and, for the captain, 解散小队 (Tracy, 2026-11-21) on 小队设置: either way the member is out
// of the squad, and the app goes back to sign-up's squad step.
extension SquadSettingsModel {
    /// Leaves the squad. The app then goes back to sign-up's squad step.
    public func leave() async {
        guard let settings else { return }
        await change { service throws(SquadError) in
            try await service.remove(settings.viewer, from: settings.squad.id)
            self.hasLeft = true
        }
    }

    /// Disbands the squad (解散小队), for its captain: everyone is out of it at once. The app then
    /// goes back to sign-up's squad step, as after leaving.
    public func disband() async {
        guard let settings, isCaptain else { return }
        await change { service throws(SquadError) in
            try await service.disband(settings.squad.id)
            self.hasLeft = true
        }
    }

    /// Whether 解散小队 is offered: to the captain while anyone else is in the squad (alone, 退出小队
    /// already ends it).
    public var canDisband: Bool { isCaptain && (settings?.squad.members.count ?? 0) > 1 }
}
