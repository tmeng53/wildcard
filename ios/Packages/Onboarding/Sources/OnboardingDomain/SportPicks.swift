import Contracts

/// 平时练什么？: the sports a new member usually does, in the order picked. They become the
/// choices for each training day of the week that follows. The character puts on the kit of the
/// last one picked; taking that one off puts on the one picked before it, or everyday clothes.
public struct SportPicks: Hashable, Sendable {
    /// 最常见, as a two-column grid: the sports with a kit of their own.
    public static let common: [Sport] = [.swim, .run, .strength, .tennis, .climb, .yoga]
    /// 更多, as a row of pills, before 其他 and search.
    public static let more: [Sport] = [
        .roadCycling, .matPilates, .badminton, .hike, .basketball, .ski, .pickleball, .dance, .boxing, .soccer,
    ]
    public private(set) var picked: [Activity] = []

    public init(_ picked: [Activity] = []) {
        for activity in picked { _ = toggle(activity) }
    }

    /// What the character wears now: the latest pick, or nil for everyday clothes.
    public var wearing: Activity? { picked.last }

    public func contains(_ activity: Activity) -> Bool { picked.contains(activity) }

    /// What a tap did, so the screen knows whether the character changes.
    public enum Toggle: Equatable, Sendable {
        /// Picked: the character changes into its kit.
        case picked
        /// Taken off. `changed` when it was the one being worn.
        case removed(changed: Bool)
    }

    /// Picks `activity`, or takes it off if picked.
    public mutating func toggle(_ activity: Activity) -> Toggle {
        if let index = picked.firstIndex(of: activity) {
            let wasWorn = index == picked.count - 1
            picked.remove(at: index)
            return .removed(changed: wasWorn)
        }
        picked.append(activity)
        return .picked
    }
}
