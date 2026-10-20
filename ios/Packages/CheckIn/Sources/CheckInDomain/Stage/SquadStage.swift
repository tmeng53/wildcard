import Contracts

/// A teammate as the home scene places them.
public struct StageMember: Hashable, Sendable {
    public let id: MemberID
    public let status: StageStatus
    /// Their first check-in today, of any kind. Earlier ones get the nearer, more central spots.
    public let firstCheckInAt: Timestamp?
    /// 社恐 takes the last free spot instead of the best.
    public let keepsToTheBack: Bool

    public init(id: MemberID, status: StageStatus, firstCheckInAt: Timestamp?, keepsToTheBack: Bool) {
        self.id = id
        self.status = status
        self.firstCheckInAt = firstCheckInAt
        self.keepsToTheBack = keepsToTheBack
    }
}

/// Where a teammate is.
public enum StagePlacement: Hashable, Sendable {
    /// Using a slot of the scene's equipment.
    case station(StationKind, slot: Int)
    /// Training in place on the playing area, while nobody uses the scene's equipment.
    case field(StagePoint)
    /// On the open floor: training in place, holding a 请假条, sitting or standing.
    case floor(StagePoint)
}

/// Who stands where on the home scene. People keep their spot, except for these moves: to or
/// from the equipment, from the floor onto the playing area when they start training while the
/// equipment is idle and a spot there is free, and from the playing area back to the floor once
/// someone takes the equipment. Arrange the same stage again to keep it.
public struct SquadStage: Hashable, Sendable {
    public let layout: StageLayout
    public private(set) var placements: [MemberID: StagePlacement]
    /// Who was training at the last arrangement, so only starting to train moves someone onto
    /// the playing area.
    private var training: Set<MemberID>

    public init(layout: StageLayout) {
        self.layout = layout
        placements = [:]
        training = []
    }

    /// Places `teammates` (everyone but me, who is always front and centre).
    ///
    /// 1. Teammates whose sport the scene has equipment for take a free slot, in the order they
    ///    checked in.
    /// 2. While nobody uses the equipment, anyone else training takes the playing area, middle out.
    /// 3. Everyone else stands on the open floor: on their old spot if it is still free (someone
    ///    already training stays on the floor rather than hopping onto the playing area), else on
    ///    the best free one (earliest check-ins first, those not checked in after); 社恐 take the
    ///    last free spot.
    public mutating func arrange(_ teammates: [StageMember]) {
        let ordered = Self.byCheckIn(teammates)
        var next = stations(for: ordered)
        let equipmentIdle = next.isEmpty
        var taken: [StagePoint] = []
        // A spot is free while nobody stands on it or close enough to be drawn over them.
        func isFree(_ spot: StagePoint) -> Bool { !taken.contains { StageLayout.crowds($0, spot) } }
        let rest = ordered.filter { next[$0.id] == nil }
        // Old spots are kept first, so nobody is pushed off theirs by someone newer.
        var startedOnFloor: [StageMember] = []
        for member in rest {
            let mayTakeField = equipmentIdle && isTraining(member)
            switch placements[member.id] {
            case .field(let spot)? where mayTakeField && isFree(spot):
                taken.append(spot)
                next[member.id] = .field(spot)
            case .floor(let spot)? where isFree(spot):
                // Held even for someone who just started training, so nobody takes it while
                // they wait for a spot on the playing area.
                taken.append(spot)
                next[member.id] = .floor(spot)
                if mayTakeField && !training.contains(member.id) { startedOnFloor.append(member) }
            default:
                continue
            }
        }
        // Someone who just started training moves onto the playing area if a spot is free there.
        for member in startedOnFloor {
            guard case .floor(let old)? = next[member.id] else { continue }
            taken.removeAll { $0 == old }
            if let spot = layout.field.first(where: isFree) {
                taken.append(spot)
                next[member.id] = .field(spot)
            } else {
                taken.append(old)
            }
        }
        placeNew(rest.filter { next[$0.id] == nil }, equipmentIdle: equipmentIdle, in: &next, taken: &taken)
        placements = next
        training = Set(teammates.filter(isTraining).map(\.id))
    }

    /// Places those without a spot yet, in order: a trainer onto the playing area while the
    /// equipment is idle and it has room, everyone else on the best free floor spot (社恐 the last).
    private func placeNew(
        _ members: [StageMember], equipmentIdle: Bool, in next: inout [MemberID: StagePlacement],
        taken: inout [StagePoint]
    ) {
        for member in members {
            let spots = taken
            let isFree = { (spot: StagePoint) in !spots.contains { StageLayout.crowds($0, spot) } }
            if equipmentIdle && isTraining(member), let spot = layout.field.first(where: isFree) {
                taken.append(spot)
                next[member.id] = .field(spot)
                continue
            }
            let free = layout.floor.filter(isFree)
            guard let spot = member.keepsToTheBack ? free.last : free.first else { continue }
            taken.append(spot)
            next[member.id] = .floor(spot)
        }
    }

    /// The equipment slots for `ordered`: everyone keeps the slot they had if their sport still
    /// uses it, then the rest take free slots in order.
    private func stations(for ordered: [StageMember]) -> [MemberID: StagePlacement] {
        var next: [MemberID: StagePlacement] = [:]
        var used: [StationKind: Set<Int>] = [:]
        for member in ordered {
            guard case .station(let kind, let slot) = placements[member.id],
                sport(of: member).map({ uses($0, kind) }) == true,
                used[kind, default: []].contains(slot) == false
            else { continue }
            used[kind, default: []].insert(slot)
            next[member.id] = .station(kind, slot: slot)
        }
        for member in ordered where next[member.id] == nil {
            guard let sport = sport(of: member), let slot = freeSlot(for: sport, used: used) else { continue }
            used[slot.kind, default: []].insert(slot.slot)
            next[member.id] = .station(slot.kind, slot: slot.slot)
        }
        return next
    }

    private func isTraining(_ member: StageMember) -> Bool {
        if case .trained = member.status { true } else { false }
    }

    private func sport(of member: StageMember) -> Sport? {
        if case .trained(.sport(let sport)?) = member.status { sport } else { nil }
    }

    private func uses(_ sport: Sport, _ kind: StationKind) -> Bool {
        layout.stationsBySport[sport]?.contains(kind) == true
    }

    private func freeSlot(for sport: Sport, used: [StationKind: Set<Int>]) -> (kind: StationKind, slot: Int)? {
        for kind in layout.stationsBySport[sport] ?? [] {
            guard let station = layout.station(kind) else { continue }
            if let slot = (0..<station.capacity).first(where: { !used[kind, default: []].contains($0) }) {
                return (kind, slot)
            }
        }
        return nil
    }

    /// Checked in first to last, then those not checked in; ties keep the squad's order.
    static func byCheckIn(_ members: [StageMember]) -> [StageMember] {
        members.enumerated().sorted { lhs, rhs in
            switch (lhs.element.firstCheckInAt, rhs.element.firstCheckInAt) {
            case (let left?, let right?) where left != right: left < right
            case (.some, nil): true
            case (nil, .some): false
            default: lhs.offset < rhs.offset
            }
        }.map(\.element)
    }
}
