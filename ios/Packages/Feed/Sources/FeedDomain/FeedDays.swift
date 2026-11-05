import Contracts

/// What a day's section is called, relative to the viewer's today. The app turns it into words.
public enum DayHeading: Hashable, Sendable {
    /// 今天
    case today
    /// 昨天
    case yesterday
    /// An earlier day of this week (Monday to Sunday): 周一 is 1, 周日 7.
    case weekday(Int)
    /// Before this week: the date itself.
    case date(LocalDay)

    public init(_ day: LocalDay, today: LocalDay) {
        if day >= today {
            self = .today
        } else if day == today.adding(days: -1) {
            self = .yesterday
        } else if day >= today.weekStart {
            self = .weekday(day.weekday)
        } else {
            self = .date(day)
        }
    }
}

/// The day a 补打卡 counts for, said from the day it was posted, after the post's time on
/// 动态 (补周日的). Nil for a post made the day it counts for.
public enum BackfillDay: Hashable, Sendable {
    /// 补昨天的
    case yesterday
    /// 补周一的 (1) to 补周日的 (7): a day in the six before the posted day.
    case weekday(Int)
    /// 补上周二的: the same weekday a week before, the furthest a post can go back.
    case weekdayLastWeek(Int)

    public init?(_ checkIn: CheckIn) {
        let posted = checkIn.postedDay
        guard checkIn.day < posted else { return nil }
        if checkIn.day == posted.adding(days: -1) {
            self = .yesterday
        } else if checkIn.day.weekday == posted.weekday {
            self = .weekdayLastWeek(checkIn.day.weekday)
        } else {
            self = .weekday(checkIn.day.weekday)
        }
    }
}

/// One day of the feed: its posts, newest first.
public struct FeedSection: Hashable, Sendable, Identifiable {
    public let day: LocalDay
    public let heading: DayHeading
    public let posts: [FeedPost]

    public var id: LocalDay { day }

    /// Posts grouped by the day they were posted (a 补打卡 sits on the day it went up, not the
    /// day it counts for), newest day first.
    public static func sections(_ posts: [FeedPost], today: LocalDay) -> [FeedSection] {
        Dictionary(grouping: posts, by: \.checkIn.postedDay)
            .sorted { $0.key > $1.key }
            .map { day, posts in
                FeedSection(
                    day: day, heading: DayHeading(day, today: today),
                    posts: posts.sorted {
                        ($0.checkIn.createdAt, $0.id.description) > ($1.checkIn.createdAt, $1.id.description)
                    })
            }
    }
}

/// The days one load asks for. The feed loads a week at a time and goes further back as the
/// member scrolls; the API answers at most 31 days a call.
public struct FeedRange: Hashable, Sendable {
    public static let days = 7

    public let first: LocalDay
    public let last: LocalDay

    /// The latest week, up to the viewer's today. A teammate far ahead in time can post for the
    /// next day, so `last` reaches one day past it.
    public static func latest(today: LocalDay) -> FeedRange {
        FeedRange(first: today.adding(days: 1 - days), last: today.adding(days: 1))
    }

    /// The week before this one.
    public var earlier: FeedRange {
        FeedRange(first: first.adding(days: -Self.days), last: first.adding(days: -1))
    }
}
