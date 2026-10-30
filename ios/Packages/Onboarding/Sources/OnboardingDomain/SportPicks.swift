import Contracts

/// 平时练什么？: the sports a new member usually does, in the order picked. They become the
/// choices for each training day of the week that follows. The character puts on the kit of the
/// last one picked; taking that one off puts on the one picked before it, or everyday clothes.
/// Which sports 最常见 shows is the sports list's (`SportCatalog.signUpCommon`), data the API
/// serves; 更多 opens the whole list.
public struct SportPicks: Hashable, Sendable {
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
