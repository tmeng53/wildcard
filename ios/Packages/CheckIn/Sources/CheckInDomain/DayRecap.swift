import Contracts
import Foundation

/// 今日赛况: the squad's day as a box score, opened from a tag on the home card from the evening
/// on, without a push. It only says what people did: whoever hasn't checked in has no row and
/// isn't counted as missing.
public struct DayRecap: Hashable, Sendable {
    /// What a member's line says.
    public enum RowKind: Hashable, Sendable {
        /// Their latest 练了, and the latest meal they logged today.
        case trained(Activity, meal: MealKind?)
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
    /// Today's recap, from the squad's today and its check-ins the home holds.
    public var recap: DayRecap {
        var trained: [(at: Timestamp, row: DayRecap.Row)] = []
        var disclaimers: [(at: Timestamp, row: DayRecap.Row)] = []
        var resting: [DayRecap.Row] = []
        var healthy = 0
        var cheat = 0
        for mate in today.members {
            let posts = todaysCheckIns(of: mate.member)
            healthy += posts.count { if case .healthyMeal = $0.entry { true } else { false } }
            cheat += posts.count { if case .cheatMeal = $0.entry { true } else { false } }
            let firstTraining = posts.first { if case .trained = $0.entry { true } else { false } }
            if let firstTraining, let activity = todaysSport(of: mate.member) {
                let meal = posts.reversed().lazy.compactMap { post -> MealKind? in
                    switch post.entry {
                    case .healthyMeal: .healthyMeal
                    case .cheatMeal: .cheatMeal
                    default: nil
                    }
                }
                .first
                trained.append(
                    (firstTraining.createdAt, .init(member: mate.member, kind: .trained(activity, meal: meal))))
            } else if let note = todaysDisclaimer(of: mate.member),
                let posted = posts.first(where: { if case .disclaimer = $0.entry { true } else { false } })
            {
                disclaimers.append((posted.createdAt, .init(member: mate.member, kind: .disclaimer(note))))
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
