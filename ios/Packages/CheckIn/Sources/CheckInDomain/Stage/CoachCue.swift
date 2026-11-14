import Contracts

/// What the coach on the sideline does when the home changes under it (Tracy, 2026-11-05, and
/// 2026-11-14: more than a whistle): it answers the newest post that arrived today by what it is,
/// my own 训练 with a cheer, a teammate's with its whistle, a 健康餐 with a thumbs-up, a 坦白放纵餐
/// with a facepalm and a 请假条 by waving it through; and claps when a week reaches its goal, mine
/// or the squad's, which wins over any post. The caller keeps the last `Sighting`. While its page
/// has a card the member hasn't seen, it whistles again and again (Tracy, 2026-11-09), every
/// `newsWhistlePeriod`; while nothing happens, it does one of its habits now and then.
public enum CoachCue: Hashable, Sendable {
    /// A teammate's 训练 arrived.
    case whistle
    /// A week reached its goal.
    case clap
    /// My own 训练 arrived.
    case myTraining
    /// A 健康餐 arrived.
    case healthyMeal
    /// A 坦白放纵餐 arrived.
    case cheatMeal
    /// A 请假条 arrived.
    case dayOff

    /// How often the coach whistles while its page has news, in seconds: its whistle, then a rest.
    public static let newsWhistlePeriod: Double = 3

    /// How long the coach stands still between habits, in seconds: a wait picked in this range
    /// each time, so it never looks like a timer.
    public static let habitWait: ClosedRange<Double> = 18...32

    /// What the coach saw on the home: today's posts and whether each week has reached its goal.
    public struct Sighting: Hashable, Sendable {
        fileprivate let posts: [CheckInID: SeenPost]
        let myGoal: Bool
        let squadGoal: Bool

        public init(_ home: Home) {
            let today = home.today.members.flatMap { home.todaysCheckIns(of: $0.member) }
            posts = Dictionary(
                today.map {
                    ($0.id, SeenPost(cue: Self.cue(for: $0, mine: $0.member == home.member), made: $0.createdAt))
                },
                uniquingKeysWith: { first, _ in first })
            myGoal = Self.reached(home.today.myWeek.week)
            squadGoal = Self.reached(home.today.squadWeek)
        }

        private static func cue(for post: CheckIn, mine: Bool) -> CoachCue {
            switch post.entry {
            case .trained: mine ? .myTraining : .whistle
            case .healthyMeal: .healthyMeal
            case .cheatMeal: .cheatMeal
            case .disclaimer: .dayOff
            }
        }

        private static func reached(_ week: WeekCount) -> Bool {
            week.plannedDays > 0 && week.trainedDays >= week.plannedDays
        }
    }

    /// The cue for `now`, after the coach last saw `before`; none the first time it looks, so a
    /// home opening on posts it never saw arrive stays quiet.
    public static func after(_ before: Sighting?, now: Sighting) -> CoachCue? {
        guard let before else { return nil }
        if (now.myGoal && !before.myGoal) || (now.squadGoal && !before.squadGoal) { return .clap }
        return now.posts.filter { before.posts[$0.key] == nil }.values
            .max { ($0.made, $0.cue.order) < ($1.made, $1.cue.order) }?.cue
    }

    /// Which of two posts made at the same moment the coach answers: a 训练 first.
    fileprivate var order: Int {
        switch self {
        case .myTraining: 5
        case .whistle: 4
        case .healthyMeal: 3
        case .cheatMeal: 2
        case .dayOff: 1
        case .clap: 0
        }
    }
}

/// A post as the coach answers it, and when it was made, so the newest of several wins.
private struct SeenPost: Hashable, Sendable {
    let cue: CoachCue
    let made: Timestamp
}
