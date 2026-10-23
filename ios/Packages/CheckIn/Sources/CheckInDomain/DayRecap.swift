import Contracts
import Foundation

/// 今日赛况: the squad's day as a box score, opened from a tag on the home card from the evening
/// on, without a push. It only says what people did: whoever hasn't checked in has no row and
/// isn't counted as missing.
public struct DayRecap: Hashable, Sendable {
    /// What a member's line says.
    public enum RowKind: Hashable, Sendable {
        /// Their latest 练了's sport, the minutes of all their 练了 today where they gave any, and
        /// the latest meal they logged today.
        case trained(Activity, minutes: Int?, meal: MealKind?)
        /// Their 请假条, word for word.
        case disclaimer(String)
        /// A rest day in their plan, with no check-in.
        case restDay
    }

    /// One member's line.
    public struct Row: Hashable, Sendable {
        public let member: MemberID
        public let kind: RowKind

        public init(member: MemberID, kind: RowKind) {
            self.member = member
            self.kind = kind
        }
    }

    /// The hour of the member's own evening the recap shows from, until their day ends.
    public static let hour = 21

    /// Members who checked in today, a 请假条 counting as it does on the squad card.
    public let showedUp: Int
    public let members: Int
    /// Who trained, by their first 练了; then 请假条s, by when posted; then planned rest days.
    public let rows: [Row]
    public let healthyMeals: Int
    public let cheatMeals: Int
}

extension Home {
    /// Today's recap, from the squad's today and its check-ins the home holds, with my posts
    /// still waiting to go out, which the squad's today already counts.
    public func recap(pending: [PendingCheckIn] = []) -> DayRecap {
        var trained: [(at: Timestamp, row: DayRecap.Row)] = []
        var disclaimers: [(at: Timestamp, row: DayRecap.Row)] = []
        var resting: [DayRecap.Row] = []
        var healthy = 0
        var cheat = 0
        for mate in today.members {
            let posts = recapPosts(of: mate, pending: pending)
            healthy += posts.count { $0.post == .healthyMeal }
            cheat += posts.count { $0.post == .cheatMeal }
            let sports = posts.compactMap { if case .trained(let activity, _) = $0.post { activity } else { nil } }
            let minutes = posts.compactMap {
                if case .trained(_, let minutes) = $0.post { minutes?.value } else { nil }
            }
            let notes = posts.compactMap { if case .disclaimer(let note) = $0.post { note } else { nil } }
            if let first = posts.first(where: { if case .trained = $0.post { true } else { false } }),
                let sport = sports.last
            {
                let meal = posts.reversed().lazy.compactMap(\.post.meal).first
                trained.append(
                    (
                        first.at,
                        .init(
                            member: mate.member,
                            kind: .trained(sport, minutes: minutes.isEmpty ? nil : minutes.reduce(0, +), meal: meal))
                    ))
            } else if let posted = posts.first(where: { if case .disclaimer = $0.post { true } else { false } }),
                let note = notes.last
            {
                disclaimers.append((posted.at, .init(member: mate.member, kind: .disclaimer(note))))
            } else if mate.plannedRest {
                resting.append(.init(member: mate.member, kind: .restDay))
            }
        }
        return DayRecap(
            showedUp: today.members.count { $0.training != .notCheckedIn }, members: today.members.count,
            rows: trained.sorted { $0.at < $1.at }.map(\.row) + disclaimers.sorted { $0.at < $1.at }.map(\.row)
                + resting,
            healthyMeals: healthy, cheatMeals: cheat)
    }

    /// A member's posts today to this squad, saved or waiting to go out, oldest first.
    private func recapPosts(of mate: SquadmateToday, pending: [PendingCheckIn]) -> [(at: Timestamp, post: RecapPost)] {
        let saved = todaysCheckIns(of: mate.member).map { checkIn -> (at: Timestamp, post: RecapPost) in
            switch checkIn.entry {
            case .trained(let training): (checkIn.createdAt, .trained(training.activity, training.minutes))
            case .healthyMeal: (checkIn.createdAt, .healthyMeal)
            case .cheatMeal: (checkIn.createdAt, .cheatMeal)
            case .disclaimer(let note): (checkIn.createdAt, .disclaimer(note.text))
            }
        }
        let waiting = pending.filter { post in
            post.member == mate.member && post.day == mate.day && post.audience.squads.contains(squad.id)
                && !checkIns.contains { $0.id == post.id }
        }
        .map { post -> (at: Timestamp, post: RecapPost) in
            switch post.draft {
            case .trained(let activity, let minutes, _): (post.createdAt, .trained(activity, minutes))
            case .healthyMeal: (post.createdAt, .healthyMeal)
            case .cheatMeal: (post.createdAt, .cheatMeal)
            case .disclaimer(let note): (post.createdAt, .disclaimer(note.text))
            }
        }
        return (saved + waiting).sorted { $0.at < $1.at }
    }

    /// Whether the recap shows at `now`: from `DayRecap.hour` on the member's own clock until
    /// their day ends, the 3am grace included.
    public func showsRecap(at now: Date) -> Bool {
        guard let day = mine?.day else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard
            let evening = calendar.date(
                from: DateComponents(year: day.year, month: day.month, day: day.day, hour: DayRecap.hour))
        else { return false }
        return now >= evening && LocalDay(at: now, in: timeZone) == day
    }
}

/// What a post says on 今日赛况, saved or still waiting to go out.
private enum RecapPost: Equatable {
    case trained(Activity, WorkoutMinutes?)
    case healthyMeal
    case cheatMeal
    case disclaimer(String)

    var meal: MealKind? {
        switch self {
        case .healthyMeal: .healthyMeal
        case .cheatMeal: .cheatMeal
        case .trained, .disclaimer: nil
        }
    }
}
