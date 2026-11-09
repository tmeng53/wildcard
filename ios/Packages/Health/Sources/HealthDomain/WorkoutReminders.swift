import Contracts
import Foundation

/// Who this phone posts for and where, as the home last loaded: what a reminder of a new
/// workout, worked out while the app is in the background, and its long-press card need to post
/// without the app open. The app keeps it in the app group; stored JSON, so it has a `version`.
public struct PostingContext: Hashable, Sendable, Codable {
    public var version = 1
    public let member: MemberID
    public let squad: SquadID
    public let squadName: String
    /// The member's time zone, which their day follows.
    public let timeZone: String
    /// The workouts the member posted, which are never reminded of.
    public let posted: Set<WorkoutSource>

    public init(member: MemberID, squad: SquadID, squadName: String, timeZone: String, posted: Set<WorkoutSource>) {
        self.member = member
        self.squad = squad
        self.squadName = squadName
        self.timeZone = timeZone
        self.posted = posted
    }

    public var zone: TimeZone { TimeZone(identifier: timeZone) ?? .gmt }
}

/// A new workout's post, ready to go from its reminder's long-press card with one tap: the
/// member, squad and day it was worked out for, its sport, and the workout as Health has it with
/// what 设置 › Apple 健康 shares. Stored JSON (the reminder carries it), so it has a `version`.
public struct QuickPost: Hashable, Sendable, Codable {
    public var version = 1
    public let member: MemberID
    public let squad: SquadID
    public let squadName: String
    /// The member's day the workout ended on: a reminder is only for today's.
    public let day: LocalDay
    /// The sport of the list it is; nil for one the list has none like, which the member names
    /// on the compose page.
    public let sport: String?
    /// The whole workout, before anything is struck.
    public let workout: Workout
    public let sharing: HealthSharing

    public init(context: PostingContext, day: LocalDay, imported: ImportedWorkout, sharing: HealthSharing) {
        member = context.member
        squad = context.squad
        squadName = context.squadName
        self.day = day
        if case .sport(let sport) = imported.activity { self.sport = sport.rawValue } else { sport = nil }
        workout = imported.workout
        self.sharing = sharing
    }

    public var activity: Activity? { sport.flatMap(Sport.init(rawValue:)).map(Activity.sport) }

    public var imported: ImportedWorkout { ImportedWorkout(workout: workout, activity: activity) }

    /// The numbers it starts with struck: what 设置 doesn't share.
    public var startsStruck: Set<WorkoutCell> { sharing.struck }

    /// The workout as posted with `struck` taken out: no photos, so the kept map, then the kept
    /// chart, lead the post.
    public func posting(struck: Set<WorkoutCell>) -> Workout {
        let tiles = sharing.keptTiles(of: workout)
        let positions = Dictionary(uniqueKeysWithValues: tiles.enumerated().map { ($1, $0 + 1) })
        return workout.posting(struck: struck, positions: positions)
    }
}

/// Which of the workouts read from Health get a reminder: today's on the member's clock, ended
/// within the last `freshHours`, neither posted nor reminded of before, newest first.
public enum WorkoutReminders {
    /// A workout synced later than this after it ended isn't news any more; it still shows on
    /// 今天's card and 打卡.
    public static let freshHours = 3.0
    /// How many reminded workouts the phone remembers, more than a day of workouts.
    public static let rememberedMax = 30

    public static func due(
        _ workouts: [ImportedWorkout], context: PostingContext, reminded: Set<WorkoutSource>, now: Date
    ) -> [ImportedWorkout] {
        let today = LocalDay(at: now, in: context.zone)
        let since = now.addingTimeInterval(-freshHours * 3600)
        return workouts.today(today, in: context.zone, posted: context.posted)
            .filter { !$0.isPosted && !reminded.contains($0.id) && $0.imported.workout.endedAt.date >= since }
            .map(\.imported)
    }
}

/// What became of a post from a reminder's long-press card.
public enum QuickPostOutcome: Hashable, Sendable {
    /// The server saved it.
    case posted
    /// It couldn't go out (offline, or the sign-in needs the app); it goes out when the app opens.
    case waiting
    /// The server refused it, such as a workout posted already.
    case refused
}

/// Posts a reminder's workout without the app open. The app's extension passes `Backend`'s
/// `APIQuickPoster`, which keeps the post where the app sends it from if it can't go out.
public protocol QuickPosting: Sendable {
    /// - Parameter caption: the line the member typed under it, if any (empty for none).
    func post(_ post: QuickPost, struck: Set<WorkoutCell>, caption: String) async -> QuickPostOutcome
}
