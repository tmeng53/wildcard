import Contracts

/// A move the AI may pick for a character: AWARD_MOVES in the story template. The API sends it
/// as an open string, so a move added later doesn't break this build: anything unknown plays
/// the persona's own cheer.
public enum AwardMove: String, CaseIterable, Hashable, Sendable {
    /// The persona's own check-in cheer.
    case cheer
    case pump, pose, wave, laugh, stretch, warmup, doze, flat, fullbelly
    /// 叠罗汉: two characters stack up. The ending's alone, since it needs a pair.
    case stack

    public init(wire: String) {
        self = AwardMove(rawValue: wire) ?? .cheer
    }
}

/// A clip a character plays in the story. Award moves are the AI's pick; the rest follow from
/// the facts: a day's sport, a meal, the podium toss.
public enum StoryClip: Hashable, Sendable {
    case award(AwardMove)
    /// A trained day: its sport's kit and move, as the character editor and 上场 play them; nil
    /// for a sport the member named themselves.
    case sport(Sport?)
    /// Eating what they logged more of.
    case eat(Meals.Meal)
    /// 抛高高 on the podium: the champion goes up, the sides throw.
    case tossFlyer, tossThrower
    /// 叠罗汉 at the ending: one carries, one sits on top.
    case stackBottom, stackTop

    /// A shared clip's name in the character's art (`moves/<name>.json`); a sport's comes from
    /// its kit instead.
    public var name: String {
        switch self {
        case .award(let move): move.rawValue
        case .sport: "sport"
        case .eat(.healthy): "eat-healthy"
        case .eat(.cheat): "eat-treat"
        case .tossFlyer: "toss-flyer"
        case .tossThrower: "toss-thrower"
        case .stackBottom: "stack-bottom"
        case .stackTop: "stack-top"
        }
    }
}

extension DayKind {
    /// What the character does on this day in 你的一周: the sport's move, a doze on a rest day,
    /// lying flat (躺平) on a 请假条 day; nothing on a day with no check-in.
    public var clip: StoryClip? {
        switch self {
        case .trained(let sport): .sport(sport)
        case .rest: .award(.doze)
        case .disclaimer: .award(.flat)
        case .none: nil
        }
    }
}

extension Ending {
    /// The finale: the AI's pick when it fits the result, otherwise the result's first.
    /// 叠罗汉 needs two characters, so it is only for a hit week with two or more people.
    public func finale(castSize: Int) -> AwardMove {
        let allowed: [AwardMove] = isHit ? [.stack, .pump, .wave] : [.warmup, .stretch, .pump]
        guard let move, allowed.contains(move) else { return isHit ? .pump : .warmup }
        return move == .stack && castSize < 2 ? .pump : move
    }
}

extension AwardMove {
    /// A move for one character on its own: 叠罗汉 needs a partner, so it cheers instead.
    public var solo: AwardMove { self == .stack ? .cheer : self }
}
