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

    /// Nothing is told live here: it says it is ready, as the server's stream does on connecting,
    /// so the inbox reads its newest page at launch, then listens until the app stops.
    public func listen(_ heard: @escaping @Sendable (LiveNotice) async -> Void) async throws(NotificationsError) {
        await heard(.ready)
        let (quiet, open) = AsyncStream.makeStream(of: Never.self)
        // Ends only when the listening task is cancelled.
        for await _ in quiet {}
        open.finish()
    }

    /// The sample squad's last two weeks, told before `now`: the coach's reply, a scene move and
    /// a teammate's comment on the same post today (one row), the 6pm push yesterday, the 战报 and
    /// a store opening this week or last, and older ones, then `latest`, told just now. The newest two are new.
    public static func sample(
        now: Date, calendar: Calendar = .current, latest: [Notice.Subject] = []
    ) -> InMemoryNoticeSource {
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
        let post = CheckInID(UUID())
        let lastWeek = (try? LocalDay(year: parts.year ?? 2026, month: parts.month ?? 1, day: parts.day ?? 1))
        let subjects: [(Date, Notice.Subject)] =
            [
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
                    .coachReply(
                        checkIn: post, coach: "xiaohun", coachName: "毛头", replied: true, emoji: nil)
                ),
                (at(days: 0, hour: 10, minute: 12), .sceneMoved(scene: "track", mover: nil, moverName: "阿杰")),
                (
                    at(days: 0, hour: 11, minute: 5),
                    .comment(PushAlert(key: "push.comment", args: ["Coco", "这组深蹲太稳了"]), checkIn: post)
                ),
                // The coach's morning note, told last so the rows before it keep their numbers.
                (at(days: 0, hour: 11, minute: 30), .coachNote(sampleNote(on: at(days: 0, hour: 11)))),
            ] + latest.map { (now.addingTimeInterval(-30), $0) }
        let notices = subjects.enumerated().map { index, told in
            Notice(id: NoticeID(rawValue: index + 1), toldAt: told.0, squad: nil, subject: told.1)
        }
        return InMemoryNoticeSource(notices, seen: NoticeID(rawValue: notices.count - 2 - latest.count))
    }

    /// A holiday's pre-holiday broadcast in its celebration style, for the sample squad: TURKEY
    /// TROT's (`trot`) or JINGLE JOG's (`jingle`), giving pieces the bundled art has, since the
    /// holiday pieces are only uploaded. Its id is new on each launch, so this phone shows it
    /// every time.
    public static func celebration(_ store: String) -> Notice.Subject {
        let christmas = store == "jingle"
        let words = { (hans: String, english: String) in
            CatalogNames(simplifiedChinese: hans, english: english, traditionalChinese: hans)
        }
        let gifts = (christmas ? ["warmup-beanie", "powder-scarf", "powder-edamame"] : ["lap-bib", "moss-boots"])
            .map { Broadcast.Gift(kind: .piece, id: $0) }
        return .broadcast(
            Broadcast(
                id: "\(store)-soon-\(UUID().uuidString)",
                title: christmas ? words("圣诞节快到了", "Christmas is coming") : words("感恩节快到了", "Thanksgiving is coming"),
                body: words("商店街上新了，快去看看吧！", "New in the shops. Go take a look!"),
                action: Broadcast.Action(label: words("去商店街看看", "Go to the shops"), destination: .stores),
                style: .celebration, icon: Broadcast.Gift(kind: .store, id: store), gifts: gifts))
    }

    /// 毛头's morning note, as the approved 便条 shows it.
    private static func sampleNote(on day: Date) -> CoachMemberNote {
        CoachMemberNote(
            id: 1, squad: SquadID(UUID()), day: LocalDay(at: day, in: .current),
            text: "今天出赛表写的是力量。病刚好，重量先打八折，我在场边数着。", coach: CoachSpeaker(id: "xiaohun", name: "毛头"))
    }

    /// No notices at all, as for a member who just joined.
    public static let empty = InMemoryNoticeSource([])
}
