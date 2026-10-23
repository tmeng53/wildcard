import Contracts

/// A teammate as the home scene places them.
public struct StageMember: Hashable, Sendable {
    public let id: MemberID
    public let status: StageStatus
    /// Their first check-in today, of any kind. Earlier ones pick their spot first.
    public let firstCheckInAt: Timestamp?
    /// 社恐 takes the free spot furthest back.
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
    /// Somewhere on the scene: training in place, holding a 请假条, sitting or standing.
    case floor(StagePoint)
}

/// Who stands where on the home scene. People keep their spot, except to go to or from the
/// equipment, or off a lane someone starts running. Arrange the same stage again to keep it.
public struct SquadStage: Hashable, Sendable {
    public let layout: StageLayout
    public private(set) var placements: [MemberID: StagePlacement]

    public init(layout: StageLayout) {
        self.layout = layout
        placements = [:]
    }

    /// Places `teammates` (everyone but me, who is always front and centre).
    ///
    /// 1. Teammates whose sport the scene has equipment for take a free slot, in the order they
    ///    checked in.
    /// 2. Everyone else, whatever they are doing, is scattered over the scene, the track and
    ///    the court included but off any lane someone is running: on their old spot if it is
    ///    still free, else (earliest check-ins first, those not checked in after) on the free
    ///    spot that keeps everyone well apart; 社恐 take the free spot furthest back.
    public mutating func arrange(_ teammates: [StageMember]) {
        let ordered = Self.byCheckIn(teammates)
        var next = stations(for: ordered)
        let running = runningLanes(next)
        let open = layout.floor.filter { spot in !running.contains { $0.blocks(spot) } }
        var taken: [StagePoint] = []
        // A spot is free while nobody stands on it or close enough to be drawn over them.
        func isFree(_ spot: StagePoint) -> Bool { !taken.contains { StageLayout.crowds($0, spot) } }
        // Old spots are kept first, so nobody is pushed off theirs by someone newer.
        for member in ordered where next[member.id] == nil {
            if case .floor(let spot)? = placements[member.id], open.contains(spot), isFree(spot) {
                taken.append(spot)
                next[member.id] = .floor(spot)
            }
        }
        for member in ordered where next[member.id] == nil {
            let free = open.filter(isFree)
            let spot = member.keepsToTheBack ? Self.furthestBack(free) : Self.apart(free, from: taken)
            guard let spot else { continue }
            taken.append(spot)
            next[member.id] = .floor(spot)
        }
        placements = next
    }

    /// How far apart two spots look, depth counting more as it does on screen.
    private static func distance(_ one: StagePoint, _ other: StagePoint) -> Double {
        let across = one.x - other.x
        let deep = (one.y - other.y) * 1.4
        return (across * across + deep * deep).squareRoot()
    }

    /// The free spot furthest from everyone placed and from me, counting any distance past
    /// `roomy` as roomy enough; among those, the nearest to me, so a small squad isn't flung
    /// to the corners.
    private static func apart(_ free: [StagePoint], from taken: [StagePoint]) -> StagePoint? {
        let roomy = 200.0
        let others = taken + [StageLayout.mySpot]
        func room(_ spot: StagePoint) -> Double { min(roomy, others.map { distance($0, spot) }.min() ?? roomy) }
        return free.enumerated().min { lhs, rhs in
            (-room(lhs.element), distance(lhs.element, StageLayout.mySpot), lhs.offset)
                < (-room(rhs.element), distance(rhs.element, StageLayout.mySpot), rhs.offset)
        }?.element
    }

    /// The free spot furthest back, the most central of those.
    private static func furthestBack(_ free: [StagePoint]) -> StagePoint? {
        free.enumerated().min { ($0.element.y, $0.offset) < ($1.element.y, $1.offset) }?.element
    }

    /// The lanes someone is running in `placements`, as a strip across the scene.
    private func runningLanes(_ placements: [MemberID: StagePlacement]) -> [StageRect] {
        placements.values.compactMap { placement in
            guard case .station(let kind, let slot) = placement, let lap = layout.station(kind)?.lap(ofSlot: slot)
            else { return nil }
            // Clear of the runners' bodies too, which rise above the lane.
            return StageRect(x: 0...StageLayout.width, y: (lap.y - 40)...lap.y)
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
