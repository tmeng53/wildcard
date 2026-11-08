import Foundation

/// A notice's id: the order notices were told in, a later one larger.
public struct NoticeID: RawRepresentable, Hashable, Comparable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: NoticeID, rhs: NoticeID) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Something the member was told, as 通知 (the bell on 动态) lists it: every push sent to them
/// and every in-app notice, kept forever.
public struct Notice: Hashable, Sendable, Identifiable {
    /// What it is about. The server may add kinds; the app reads only these.
    public enum Subject: Hashable, Sendable {
        /// The 6pm push, in the words it was sent with.
        case dailyProgress(PushAlert)
        /// The week starting `week`'s 战报 is in.
        case weeklyAwards(PushAlert, week: LocalDay)
        /// A teammate moved the squad to `scene`: `mover` and their nickname now, both nil once
        /// they deleted their account.
        case sceneMoved(scene: String, mover: MemberID?, moverName: String?)
        /// The squad's coach answered the member's check-in, with a line, its emoji or both.
        case coachReply(checkIn: CheckInID, coach: CoachID, coachName: String?, replied: Bool, emoji: Emoji?)
        /// The squad's coach left the member its morning note (便条), only for them.
        case coachNote(CoachMemberNote)
        /// The squad changed coach, and the coach that left wrote the one that took over a letter.
        case coachLetter(CoachLetter)
        /// A store or prop opened by training: its id in the art.
        case unlocked(Unlock.Kind, item: String)
        /// A teammate commented on the member's check-in or replied to them there, in the words
        /// the push put it in (who, and what they wrote).
        case comment(PushAlert, checkIn: CheckInID)
        /// A notice we sent every member.
        case broadcast(Broadcast)
        /// The member's squad trained over its weekly goal some weeks in a row, so they, its
        /// captain, are suggested a higher one.
        case goalSuggestion(GoalSuggestion)
    }

    public let id: NoticeID
    public let toldAt: Date
    /// The squad it is about, if any.
    public let squad: SquadID?
    public let subject: Subject

    public init(id: NoticeID, toldAt: Date, squad: SquadID?, subject: Subject) {
        (self.id, self.toldAt, self.squad, self.subject) = (id, toldAt, squad, subject)
    }
}

/// A higher weekly goal suggested to a squad's captain (连续 3 周超过小队目标 · 改成人均 4 天？).
public struct GoalSuggestion: Hashable, Sendable {
    /// How many weeks in a row the squad trained over its goal.
    public let weeks: Int
    /// The goal suggested, 人均 N 天.
    public let daysPerMember: Int

    public init(weeks: Int, daysPerMember: Int) {
        (self.weeks, self.daysPerMember) = (weeks, daysPerMember)
    }
}

/// A push's words as it was sent: a key in the app's String Catalog and its placeholders'
/// values, in order.
public struct PushAlert: Hashable, Sendable {
    public let key: String
    public let args: [String]

    public init(key: String, args: [String] = []) {
        self.key = key
        self.args = args
    }
}

/// A page of the member's notices, newest first.
public struct NoticePage: Hashable, Sendable {
    /// The ones this build can read; a page may hold none and still have a `next`.
    public let notices: [Notice]
    /// The newest one the member has seen; nil before they first opened 通知.
    public let seenThrough: NoticeID?
    /// Where the next, older page starts; nil on the last.
    public let next: NoticeID?

    public init(notices: [Notice], seenThrough: NoticeID?, next: NoticeID?) {
        (self.notices, self.seenThrough, self.next) = (notices, seenThrough, next)
    }
}

/// What the live stream of notices says.
public enum LiveNotice: Hashable, Sendable {
    /// It is listening: what was told before now is on the newest page.
    case ready
    /// A notice just told; nil for a kind this build can't show.
    case told(Notice?)
    /// What the member's 商店街 shows may have changed (a store, piece, rule or switch, or one of
    /// their unlocks): its shelf is read again.
    case shelfChanged
}
