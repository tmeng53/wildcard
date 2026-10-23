import Contracts

/// Day or night on the scene. At night the lights come on, anyone training keeps going and
/// everyone else sleeps where they are, 请假条 put away.
public enum DayPhase: Hashable, Sendable {
    case day
    case night

    /// Night runs from 7pm to 6am, on the member's own clock.
    public init(hour: Int) {
        self = (6..<19).contains(hour) ? .day : .night
    }
}

/// What a teammate is doing where they are.
public enum StagePose: Hashable, Sendable {
    /// On the scene's equipment.
    case station(StationKind)
    /// Training in place in their sport's kit. Swimmers and climbers away from water and wall
    /// warm up instead. No activity when it didn't arrive.
    case inPlace(Activity?)
    /// Awake, holding their 请假条 up.
    case holdingSign
    /// A rest day: sitting on the floor, cheering when someone checks in.
    case sitting
    /// Not checked in yet: standing in everyday clothes.
    case standing
    case asleep
}

/// Where someone is at a moment, and which way they face (1 right, -1 left).
public struct StagePosition: Hashable, Sendable {
    public let point: StagePoint
    public let facing: Double
    public let scale: Double

    /// Where I stand: front and centre, facing right, a little bigger than the squad.
    public static let mine = StagePosition(point: StageLayout.mySpot, facing: 1, scale: StageLayout.myScale)
}

extension SquadStage {
    public func pose(of member: StageMember, at phase: DayPhase) -> StagePose {
        if case .trained(let activity) = member.status {
            if case .station(let kind, _) = placements[member.id] { return .station(kind) }
            return .inPlace(activity)
        }
        if phase == .night { return .asleep }
        switch member.status {
        case .disclaimer: return .holdingSign
        case .restDay: return .sitting
        case .notYet, .trained: return .standing
        }
    }

    /// Where `member` is `seconds` into the day's loop: people on a track, lane or wall move
    /// along it at its speed, evenly spaced; everyone else stays on their spot,
    /// facing the middle.
    public func position(of member: MemberID, at seconds: Double) -> StagePosition? {
        switch placements[member] {
        case .floor(let point)?:
            return StagePosition(
                point: point, facing: point.x > StageLayout.mySpot.x ? -1 : 1,
                scale: StageLayout.scale(atDepth: point.y))
        case .station(let kind, let slot)?:
            guard let station = layout.station(kind) else { return nil }
            return Self.position(on: station, slot: slot, at: seconds)
        case nil:
            return nil
        }
    }

    static func position(on station: Station, slot: Int, at seconds: Double) -> StagePosition {
        let point: StagePoint
        let facing: Double
        switch station.path {
        case .lanes(let lanes, let speed):
            let lane = lanes[slot % lanes.count]
            let width = lane.to - lane.from
            let along = wrap(Double(slot) * 0.37 * 2 * width + seconds * speed, 2 * width)
            let out = along < width
            point = StagePoint(x: out ? lane.from + along : lane.to - (along - width), y: lane.y)
            facing = out ? 1 : -1
        case .climb(let columns, let speed):
            let column = columns[slot % columns.count]
            let height = column.bottom - column.top
            let along = wrap(Double(slot) * 0.29 * 2 * height + seconds * speed, 2 * height)
            point = StagePoint(
                x: column.x, y: along < height ? column.bottom - along : column.top + (along - height))
            facing = 1
        case .spots(let spots):
            point = spots[slot % spots.count]
            facing = point.x > StageLayout.mySpot.x ? -1 : 1
        }
        return StagePosition(point: point, facing: facing, scale: station.scale ?? StageLayout.scale(atDepth: point.y))
    }

    private static func wrap(_ value: Double, _ length: Double) -> Double {
        let rest = value.truncatingRemainder(dividingBy: length)
        return rest < 0 ? rest + length : rest
    }

    /// Who joins in when I check in, in the order given: everyone awake who isn't training
    /// (they keep going), so nobody at night. The screen times each cheer by persona.
    public func cheerers(_ teammates: [StageMember], at phase: DayPhase) -> [MemberID] {
        teammates.filter { member in
            if case .trained = member.status { return false }
            return pose(of: member, at: phase) != .asleep
        }
        .map(\.id)
    }
}
