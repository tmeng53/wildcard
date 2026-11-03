import Contracts

/// The squad celebrating together on the home scene (小人新动作, approved 2026-10-20: 11 撞头,
/// 12 人浪, 14 撞头 with a 社恐, 16 叠罗汉). At most one plays each time the home opens, and each
/// kind once a day on this phone: the caller keeps which kinds it showed today.
public enum SquadCelebration: Hashable, Sendable {
    /// Two members trained the same sport today: `top` hops onto `bottom`'s head. The one who
    /// checked in first holds the other up.
    case stack(top: MemberID, bottom: MemberID)
    /// I and a teammate both trained today: we run in and bump heads. A 社恐 teammate dodges at
    /// the last moment, so I bonk into thin air.
    case bump(mine: MemberID, mate: MemberID, dodged: Bool)
    /// The squad reached its week's training goal: everyone jumps in turn, left to right.
    case wave

    public enum Kind: String, Hashable, Sendable, CaseIterable {
        case stack, bump, wave
    }

    public var kind: Kind {
        switch self {
        case .stack: .stack
        case .bump: .bump
        case .wave: .wave
        }
    }

    /// What the squad celebrates on this open, if anything: the week's goal first, then two
    /// members on the same sport, then me and a teammate who both trained. `shown` are the kinds
    /// already played today on this phone. A member is in it only once their training arrived.
    public static func pick(
        myself: MemberID, members: [StageMember], squadWeek: WeekCount, shown: Set<Kind>
    ) -> SquadCelebration? {
        let trained = members.filter { if case .trained = $0.status { true } else { false } }
            .sorted {
                ($0.firstCheckInAt?.millisecondsSince1970 ?? .max) < ($1.firstCheckInAt?.millisecondsSince1970 ?? .max)
            }
        if !shown.contains(.wave), members.count > 1, squadWeek.plannedDays > 0,
            squadWeek.trainedDays >= squadWeek.plannedDays
        {
            return .wave
        }
        if !shown.contains(.stack), let pair = samePair(trained) {
            return .stack(top: pair.1.id, bottom: pair.0.id)
        }
        if !shown.contains(.bump), trained.contains(where: { $0.id == myself }),
            let mate = trained.first(where: { $0.id != myself })
        {
            return .bump(mine: myself, mate: mate.id, dodged: mate.keepsToTheBack)
        }
        return nil
    }

    /// The first two, by check-in time, who trained the same known sport.
    private static func samePair(_ trained: [StageMember]) -> (StageMember, StageMember)? {
        for (index, first) in trained.enumerated() {
            guard case .trained(let activity?) = first.status else { continue }
            if let second = trained.dropFirst(index + 1).first(where: { $0.status == .trained(activity) }) {
                return (first, second)
            }
        }
        return nil
    }
}
