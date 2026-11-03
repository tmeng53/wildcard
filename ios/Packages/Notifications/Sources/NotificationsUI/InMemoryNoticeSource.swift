import Contracts
import Foundation
import NotificationsDomain

/// 通知 without a server, for the sample squad, previews and UI tests: notices kept in memory,
/// read a page at a time, with how far the member has read.
public actor InMemoryNoticeSource: NoticeSource {
    private let all: [Notice]
    private var seen: NoticeID?
    private let size: Int

    /// - Parameters:
    ///   - notices: any order; they are read newest first.
    ///   - seen: the newest the member has seen, nil before they first opened 通知.
    public init(_ notices: [Notice], seen: NoticeID? = nil, size: Int = 30) {
        self.all = notices.sorted { $0.id > $1.id }
        self.seen = seen
        self.size = size
    }

    public func notices(before: NoticeID?) async throws(NotificationsError) -> NoticePage {
        let older = all.filter { notice in before.map { notice.id < $0 } ?? true }
        let page = Array(older.prefix(size))
        return NoticePage(notices: page, seenThrough: seen, next: older.count > size ? page.last?.id : nil)
    }

    public func markSeen(through: NoticeID) async throws(NotificationsError) {
        seen = max(seen ?? through, through)
    }

    /// The sample squad's last two weeks, told before `now`: a teammate's comment, a scene move
    /// and the coach's reply today, the 6pm push yesterday, the 战报 and a store opening this week or
    /// last, and older ones. The newest two are new.
    public static func sample(now: Date, calendar: Calendar = .current) -> InMemoryNoticeSource {
        let today = calendar.startOfDay(for: now)
        func at(days: Int, hour: Int, minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: days, to: today) ?? today
            let time = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
            // Today's notices are never later than now.
            return days == 0 ? min(time, now.addingTimeInterval(-60)) : time
        }
        var week = calendar
        week.firstWeekday = 2
        let monday = week.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let lastMonday = calendar.date(byAdding: .day, value: -7, to: monday) ?? monday
        let parts = calendar.dateComponents([.year, .month, .day], from: lastMonday)
        let lastWeek = (try? LocalDay(year: parts.year ?? 2026, month: parts.month ?? 1, day: parts.day ?? 1))
        let subjects: [(Date, Notice.Subject)] = [
            (
                at(days: -12, hour: 19), .unlocked(.prop, item: "racket")
            ),
            (
                at(days: -10, hour: 18),
                .dailyProgress(PushAlert(key: "push.dailyProgress.received", args: ["5", "16", "3"]))
            ),
            (at(days: -5, hour: 21), .unlocked(.store, item: "deuce")),
            (
                at(days: -2, hour: 20),
                lastWeek.map { .weeklyAwards(PushAlert(key: "push.weeklyAwards.ready"), week: $0) }
                    ?? .unlocked(.store, item: "lap")
            ),
            (
                at(days: -1, hour: 18),
                .dailyProgress(PushAlert(key: "push.dailyProgress.poke.more", args: ["9", "16", "Coco", "2"]))
            ),
            (
                at(days: 0, hour: 9, minute: 30),
                .coachReply(checkIn: CheckInID(UUID()), coach: "xiaohun", coachName: "毛头", replied: true, emoji: nil)
            ),
            (at(days: 0, hour: 10, minute: 12), .sceneMoved(scene: "track", mover: nil, moverName: "阿杰")),
            (
                at(days: 0, hour: 11, minute: 5),
                .comment(PushAlert(key: "push.comment", args: ["Coco", "这组深蹲太稳了"]), checkIn: CheckInID(UUID()))
            ),
        ]
        let notices = subjects.enumerated().map { index, told in
            Notice(id: NoticeID(rawValue: index + 1), toldAt: told.0, squad: nil, subject: told.1)
        }
        return InMemoryNoticeSource(notices, seen: NoticeID(rawValue: notices.count - 2))
    }

    /// No notices at all, as for a member who just joined.
    public static let empty = InMemoryNoticeSource([])
}
