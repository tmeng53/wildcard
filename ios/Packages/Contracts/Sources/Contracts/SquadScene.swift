/// A scene a squad trains on. The raw values are the API's ids.
public enum SceneID: String, CaseIterable, Hashable, Sendable {
    case track, pool, gym, tennis, climbing
}

/// A squad's scene this week (小队设置): last week's crown winners pick it once a week, or the
/// captain when nobody won. A squad keeps its latest pick until the next.
public struct SquadScene: Hashable, Sendable {
    /// Who picks this week's scene.
    public enum Pickers: Hashable, Sendable {
        /// Last week's crown winners (any of them on a tie), in the order they joined.
        case crown([MemberID])
        /// Nobody won the crown: the captain.
        case captain(MemberID?)

        public var members: [MemberID] {
            switch self {
            case .crown(let members): members
            case .captain(let captain): captain.map { [$0] } ?? []
            }
        }
    }

    /// This week's pick, once made; it can't be changed.
    public struct Pick: Hashable, Sendable {
        public let scene: SceneID
        /// Nil once the picker deleted their account.
        public let picker: MemberID?

        public init(scene: SceneID, picker: MemberID?) {
            self.scene = scene
            self.picker = picker
        }
    }

    /// The Monday of the week open for picking now.
    public let week: LocalDay
    public var scene: SceneID
    public var pickers: Pickers
    public var picked: Pick?
    /// The signed-in member may pick now.
    public var canPick: Bool
    /// Every scene, in the picker's order, and when the squad last trained on it.
    public var history: [SceneHistory]

    public init(
        week: LocalDay, scene: SceneID, pickers: Pickers, picked: Pick?, canPick: Bool, history: [SceneHistory]
    ) {
        self.week = week
        self.scene = scene
        self.pickers = pickers
        self.picked = picked
        self.canPick = canPick
        self.history = history
    }
}

/// How many weeks ago a squad last trained on a scene: 0 this week, nil never (it is still in
/// its carton).
public struct SceneHistory: Hashable, Sendable {
    public let scene: SceneID
    public let weeksAgo: Int?

    public init(scene: SceneID, weeksAgo: Int?) {
        self.scene = scene
        self.weeksAgo = weeksAgo
    }
}
