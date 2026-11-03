import Contracts

/// A move the AI may pick for a character, by the id the API sends: any move the character art
/// has (AvatarArt's `NamedMove`: shared moves, 动态's reaction moves, each sport kit's move). It
/// stays an open id, so a move added later needs no change here, and the art plays the persona's
/// own cheer for one it doesn't have. The story's own picks are named below.
public struct AwardMove: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(wire: String) {
        self.init(rawValue: wire)
    }

    /// The persona's own check-in cheer.
    public static let cheer = AwardMove(rawValue: "cheer")
    public static let pump = AwardMove(rawValue: "pump")
    public static let pose = AwardMove(rawValue: "pose")
    public static let wave = AwardMove(rawValue: "wave")
    public static let laugh = AwardMove(rawValue: "laugh")
    public static let stretch = AwardMove(rawValue: "stretch")
    public static let warmup = AwardMove(rawValue: "warmup")
    public static let doze = AwardMove(rawValue: "doze")
    public static let flat = AwardMove(rawValue: "flat")
    public static let fullbelly = AwardMove(rawValue: "fullbelly")
    /// 叠罗汉: two characters stack up. The ending's alone, since it needs a pair.
    public static let stack = AwardMove(rawValue: "stack")
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

    /// A name for the clip, unique per case but a sport's: the story keeps each member's bound
    /// clips by it, beside the kit.
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

extension Hottest {
    /// What the reader's character does beside their most-reacted post: the AI's move, else on a
    /// 练了 that sport's own move (in its kit), else the persona's cheer.
    public var clip: StoryClip {
        if let move { return .award(move.solo) }
        if kind == .trained, let sport { return .sport(sport) }
        return .award(.cheer)
    }
}
