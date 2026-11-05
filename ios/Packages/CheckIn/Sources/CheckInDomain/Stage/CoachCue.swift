import Contracts

/// What the coach on the sideline does when the home changes under it (Tracy, 2026-11-05):
/// it blows its whistle when someone's post arrives today, and claps when a week reaches its
/// goal, mine or the squad's, which wins over the whistle. The caller keeps the last `Sighting`.
public enum CoachCue: Hashable, Sendable {
    case whistle
    case clap

    /// What the coach saw on the home: today's posts and whether each week has reached its goal.
    public struct Sighting: Hashable, Sendable {
        let posts: Set<CheckInID>
        let myGoal: Bool
        let squadGoal: Bool

        public init(_ home: Home) {
            posts = Set(home.today.members.flatMap { home.todaysCheckIns(of: $0.member) }.map(\.id))
            myGoal = Self.reached(home.today.myWeek.week)
            squadGoal = Self.reached(home.today.squadWeek)
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
        return now.posts.subtracting(before.posts).isEmpty ? nil : .whistle
    }
}
