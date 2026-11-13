import Contracts

// 入队申请 and 入队需要审核 on 小队设置 (Tracy, 2026-11-12): the captain answers who asked to
// join and decides whether joining asks at all. Neither shows for anyone else, nor while the
// switch `joinApproval` is off.
extension SquadSettingsModel {
    /// The captain's requests and switch; nil for everyone else.
    public var joining: SquadJoining? { settings?.joining }

    /// How many are waiting for the captain's answer: the dot on 小队's gear.
    public var waitingRequests: Int { joining?.requests.count ?? 0 }

    /// Whether 同意 can let anyone in: not while the squad is full.
    public var canApprove: Bool { openSpots > 0 }

    /// The captain answers a request, while the page waits. A yes reads the squad again so the new
    /// member shows; a no takes the row away. A request answered meanwhile (on another phone, or
    /// withdrawn) reads the squad again too.
    public func answer(_ request: WaitingJoinRequest, approve: Bool) async {
        guard let settings, settings.joining != nil, !approve || canApprove else { return }
        await change { service throws(SquadError) in
            try await service.answer(request.id, in: settings.squad.id, approve: approve)
        }
        guard !changeFailed else { return }
        if approve {
            await reload()
        } else {
            update { $0.joining?.requests.removeAll { $0.id == request.id } }
        }
    }

    /// The captain turns 入队需要审核 on or off. The switch moves at once and goes back if the
    /// change doesn't go through.
    public func setJoinApproval(_ required: Bool) async {
        guard let settings, let before = settings.joining?.required, before != required else { return }
        update { $0.joining?.required = required }
        await change { service throws(SquadError) in
            let saved = try await service.setJoinApproval(of: settings.squad.id, required: required)
            self.update { $0.joining?.required = saved }
        }
        if changeFailed, case .loaded(let now) = load, now.joining?.required == required {
            update { $0.joining?.required = before }
        }
    }
}
