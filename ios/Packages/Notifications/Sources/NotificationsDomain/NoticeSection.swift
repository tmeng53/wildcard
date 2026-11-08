import Contracts
import Foundation

/// 通知's groups, in the order the page shows them.
public enum NoticeHeading: Hashable, Sendable, CaseIterable {
    /// 今天.
    case today
    /// 本周: since Monday, before today.
    case thisWeek
    /// 更早.
    case earlier
}

/// One group of 通知, newest first.
public struct NoticeSection: Hashable, Sendable, Identifiable {
    public let heading: NoticeHeading
    /// Its rows, newest first.
    public let entries: [NoticeEntry]

    public var id: NoticeHeading { heading }

    /// `notices`, newest first, under 今天, 本周 and 更早 on the member's calendar at `now`, a
    /// week starting on Monday. A group with nothing in it is left out. Pieces that came to one
    /// store together, told within `together` of each other, are one row: the newest, which
    /// opens all their boxes (Tracy, 2026-11-04). What was said on one post in one day
    /// (teammates' comments, replies and @s, and the coach's replies) is one row too (Tracy,
    /// 2026-11-08).
    public static func sections(_ notices: [Notice], now: Date, calendar: Calendar) -> [NoticeSection] {
        var calendar = calendar
        calendar.firstWeekday = 2
        let entries = Self.joiningPosts(Self.joiningPieces(notices.sorted { $0.id > $1.id }), calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let monday = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let grouped = Dictionary(grouping: entries) { entry -> NoticeHeading in
            let toldAt = entry.notice.toldAt
            return if toldAt >= today { .today } else if toldAt >= monday { .thisWeek } else { .earlier }
        }
        return NoticeHeading.allCases.compactMap { heading in
            grouped[heading].map { NoticeSection(heading: heading, entries: $0.sorted { $0.id > $1.id }) }
        }
    }

    /// How close in time pieces' notices are to count as one arrival.
    static let together: TimeInterval = 60

    /// `newestFirst` without the pieces' notices that a newer one for the same store stands for.
    private static func joiningPieces(_ newestFirst: [Notice]) -> [Notice] {
        var kept: [Notice] = []
        for notice in newestFirst {
            if let store = pieceStore(notice), let newer = kept.last, pieceStore(newer) == store,
                newer.toldAt.timeIntervalSince(notice.toldAt) <= together
            {
                continue
            }
            kept.append(notice)
        }
        return kept
    }

    /// The store a piece's notice is about: the art names each piece `<store>-<piece>`.
    private static func pieceStore(_ notice: Notice) -> Substring? {
        guard case .unlocked(.piece, let item) = notice.subject else { return nil }
        return item.split(separator: "-").first
    }

    /// `newestFirst` as rows: what was said on one post in one day joins the newest of it.
    private static func joiningPosts(_ newestFirst: [Notice], calendar: Calendar) -> [NoticeEntry] {
        struct Talk: Hashable {
            let post: CheckInID
            let day: Date
        }
        var rows: [[Notice]] = []
        var rowOf: [Talk: Int] = [:]
        for notice in newestFirst {
            guard let post = NoticeEntry.post(notice) else {
                rows.append([notice])
                continue
            }
            let talk = Talk(post: post, day: calendar.startOfDay(for: notice.toldAt))
            if let row = rowOf[talk] {
                rows[row].append(notice)
            } else {
                rowOf[talk] = rows.count
                rows.append([notice])
            }
        }
        return rows.compactMap(NoticeEntry.init)
    }
}

/// One row of 通知: a notice, or what was said on one post in one day.
public struct NoticeEntry: Hashable, Sendable, Identifiable {
    /// The newest: where the row goes, and its time.
    public let notice: Notice
    /// Every notice in the row, newest first, `notice` among them.
    public let notices: [Notice]

    public var id: NoticeID { notice.id }

    /// Someone who said something on the post.
    public enum Voice: Hashable, Sendable {
        /// A teammate, by the name the push gave.
        case teammate(String)
        /// The squad's coach, by its name, nil when it wasn't told.
        case coach(String?)
    }

    /// `notices`, newest first; nil when there are none.
    init?(_ notices: [Notice]) {
        guard let newest = notices.first else { return nil }
        self.notice = newest
        self.notices = notices
    }

    /// Whether the row stands for more than one notice.
    public var isJoined: Bool { notices.count > 1 }

    /// Who said something, newest first, each once.
    public var voices: [Voice] {
        var seen: Set<Voice> = []
        return notices.compactMap { notice -> Voice? in
            let voice: Voice? =
                switch notice.subject {
                case .comment(let alert, _): alert.args.first.map(Voice.teammate)
                case .coachReply(_, _, let name, _, _): .coach(name)
                default: nil
                }
            guard let voice, seen.insert(voice).inserted else { return nil }
            return voice
        }
    }

    /// The newest line a teammate wrote, and who wrote it.
    public var latestLine: (voice: Voice, text: String)? {
        for notice in notices {
            if case .comment(let alert, _) = notice.subject, alert.args.count >= 2 {
                return (.teammate(alert.args[0]), alert.args[1])
            }
        }
        return nil
    }

    /// Whether any of it answers the member (a reply to them or an @ of them) rather than
    /// commenting on their own post.
    public var answersMember: Bool {
        notices.contains { notice in
            guard case .comment(let alert, _) = notice.subject else { return false }
            return alert.key != "push.comment"
        }
    }

    /// The post a notice says something on: a comment's or a coach's reply's.
    static func post(_ notice: Notice) -> CheckInID? {
        switch notice.subject {
        case .comment(_, let checkIn): checkIn
        case .coachReply(let checkIn, _, _, _, _): checkIn
        default: nil
        }
    }
}
