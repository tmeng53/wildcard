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
public enum Placement: Hashable, Sendable {
    /// Using a slot of the scene's equipment.
    case station(StationKind, slot: Int)
    /// Training in place on the playing area, while nobody uses the scene's equipment.
    case field(StagePoint)
    /// On the open floor: training in place, holding a 请假条, sitting or standing.
    case floor(StagePoint)
}

/// Who stands where on the home scene. People keep their spot when their status changes; only
/// going to or from equipment moves them. Pass the last arrangement back in to keep it.
public struct SquadStage: Hashable, Sendable {
    public let layout: StageLayout
    public private(set) var placements: [MemberID: Placement]

    public init(layout: StageLayout) {
        self.layout = layout
        placements = [:]
    }

    /// Places `teammates` (everyone but me, who is always front and centre).
    ///
    /// 1. Teammates whose sport the scene has equipment for take a free slot, in the order they
    ///    checked in.
    /// 2. While nobody uses the equipment, anyone else training takes the playing area, middle out.
    /// 3. Everyone else stands on the open floor: on their old spot if it is still free, else on
    ///    the best free one (earliest check-ins first, those not checked in after); 社恐 take the
    ///    last free spot.
    public mutating func arrange(_ teammates: [StageMember]) {
        let previous = placements
        var next: [MemberID: Placement] = [:]
        let ordered = Self.byCheckIn(teammates)

        var used: [StationKind: Set<Int>] = [:]
        // Everyone keeps the slot they had if their sport still uses it.
        for member in ordered {
            guard case .station(let kind, let slot) = previous[member.id],
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

        let equipmentIdle = used.isEmpty
        var takenField = Set<StagePoint>()
        var takenFloor = Set<StagePoint>()
        let rest = ordered.filter { next[$0.id] == nil }
        // Old floor spots are kept first, so nobody is pushed off theirs by someone newer.
        for member in rest {
            let wantsField = equipmentIdle && isTraining(member)
            if wantsField, case .field(let spot) = previous[member.id], !takenField.contains(spot) {
                takenField.insert(spot)
                next[member.id] = .field(spot)
            } else if !wantsField, case .floor(let spot) = previous[member.id], !takenFloor.contains(spot) {
                takenFloor.insert(spot)
                next[member.id] = .floor(spot)
            }
        }
        for member in rest where next[member.id] == nil {
            if equipmentIdle && isTraining(member), let spot = layout.field.first(where: { !takenField.contains($0) }) {
                takenField.insert(spot)
                next[member.id] = .field(spot)
                continue
            }
            let free = layout.floor.filter { !takenFloor.contains($0) }
            guard let spot = member.keepsToTheBack ? free.last : free.first else { continue }
            takenFloor.insert(spot)
            next[member.id] = .floor(spot)
        }
        placements = next
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

extension SquadStage {
    /// The heads in the squad card, left to right: checked in, in the order they did; then rest
    /// days; then everyone not checked in yet, each group keeping the squad's order.
    public static func cardOrder(_ members: [StageMember]) -> [StageMember] {
        func group(_ member: StageMember) -> Int {
            switch member.status.ring {
            case .checkedIn: 0
            case .restDay: 1
            case .none: 2
            }
        }
        return byCheckIn(members).enumerated().sorted { lhs, rhs in
            (group(lhs.element), lhs.offset) < (group(rhs.element), rhs.offset)
        }.map(\.element)
    }
}
