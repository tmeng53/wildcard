import Foundation

/// A coach's id, such as `xiaohun`. Never changes.
public struct CoachID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    /// Nil for anything that can't be a coach's id: 2 to 40 lowercase letters, digits and
    /// dashes, starting with a letter.
    public init?(rawValue: String) {
        let scalars = rawValue.unicodeScalars
        guard (2...40).contains(scalars.count), let first = scalars.first, ("a"..."z").contains(first),
            scalars.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" })
        else { return nil }
        self.rawValue = rawValue
    }

    /// For the samples' own coaches.
    public init(stringLiteral id: String) { rawValue = id }
}

/// A coach as 教练招聘会 and its 简历 show it: the same coach for every squad. Its words come from
/// the API, so a new coach needs no app release.
public struct Coach: Hashable, Sendable, Identifiable {
    public let id: CoachID
    public let name: String
    /// Its 头衔, next to its name, such as 混混教练.
    public let title: String
    public let catchphrase: String
    /// 履历.
    public let background: String
    /// The number in 执教.
    public let yearsCoaching: Int
    /// What 执教 says after the years, such as 热情满格.
    public let experience: String
    /// 风格.
    public let style: String
    public let tags: [String]
    /// 期望待遇.
    public let pay: String

    public init(
        id: CoachID, name: String, title: String, catchphrase: String, background: String, yearsCoaching: Int,
        experience: String, style: String, tags: [String], pay: String
    ) {
        (self.id, self.name, self.title, self.catchphrase) = (id, name, title, catchphrase)
        (self.background, self.yearsCoaching, self.experience) = (background, yearsCoaching, experience)
        (self.style, self.tags, self.pay) = (style, tags, pay)
    }
}

/// A squad's coach, as its members see it in 小队设置.
public struct SquadCoach: Hashable, Sendable {
    /// The coach the squad hired, and when.
    public struct Hire: Hashable, Sendable {
        public let coach: Coach
        public let since: Date

        public init(coach: Coach, since: Date) {
            self.coach = coach
            self.since = since
        }
    }

    /// Nil while the squad has no coach.
    public let hire: Hire?
    /// The member is the captain, the only one who hires, changes and fires the coach.
    public let canHire: Bool

    public init(hire: Hire?, canHire: Bool) {
        self.hire = hire
        self.canHire = canHire
    }
}

/// The coach as members see it speak: its name, beside the 教练 tag, and its character.
public struct CoachSpeaker: Hashable, Sendable {
    public let id: CoachID
    public let name: String

    public init(id: CoachID, name: String) {
        self.id = id
        self.name = name
    }
}

/// The squad's 战术板 line: what its coach says to everyone once a day.
public struct CoachNote: Hashable, Sendable {
    /// The day it is for, on the squad's clock (`timeZone`), as the coach's daily wake keeps it.
    public let day: LocalDay
    public let text: String
    public let coach: CoachSpeaker
    public let writtenAt: Date
    /// The squad's time zone (小队时区), whose day `day` is.
    public let timeZone: TimeZone

    public init(
        day: LocalDay, text: String, coach: CoachSpeaker, writtenAt: Date, timeZone: TimeZone = CoachNote.timeZone
    ) {
        (self.day, self.text, self.coach, self.writtenAt) = (day, text, coach, writtenAt)
        self.timeZone = timeZone
    }

    /// The clock of a squad that never picked one: New York's.
    public static let timeZone = TimeZone(identifier: "America/New_York") ?? .gmt

    /// Whether it is still the line's day at `moment` on the squad's clock, so the home shows it.
    public func isCurrent(at moment: Date) -> Bool {
        LocalDay(at: moment, in: timeZone) == day
    }
}

/// What the coach said under one check-in: a line among its comments, an emoji first among its
/// reactions, or both, each with the 教练 tag. It stays after the squad fires the coach.
public struct CoachReply: Hashable, Sendable {
    public let checkIn: CheckInID
    public let coach: CoachSpeaker
    /// Nil when it only reacted.
    public let text: String?
    /// Nil when it only spoke. Not one of the post's reactions.
    public let emoji: Emoji?
    public let writtenAt: Date

    public init(checkIn: CheckInID, coach: CoachSpeaker, text: String?, emoji: Emoji?, writtenAt: Date) {
        (self.checkIn, self.coach, self.text, self.emoji, self.writtenAt) = (checkIn, coach, text, emoji, writtenAt)
    }
}

/// What the coach answered a member's reply to it (回复 毛头：…): a line shown right after that
/// reply, as a reply to its writer.
public struct CoachAnswer: Hashable, Sendable, Identifiable {
    public let checkIn: CheckInID
    /// The reply it answers.
    public let comment: CommentID
    public let coach: CoachSpeaker
    public let text: String
    public let writtenAt: Date

    public var id: CommentID { comment }

    public init(checkIn: CheckInID, comment: CommentID, coach: CoachSpeaker, text: String, writtenAt: Date) {
        (self.checkIn, self.comment, self.coach, self.text, self.writtenAt) = (checkIn, comment, coach, text, writtenAt)
    }
}

/// The coach's morning note (便条) to one member: a line only they see, once a day, which 今天
/// shows on the first open after it arrived until they put it away (收下), and 通知 keeps.
public struct CoachMemberNote: Hashable, Sendable, Identifiable {
    public let id: Int
    /// The squad whose coach wrote it.
    public let squad: SquadID
    /// The day (New York's) it was written for.
    public let day: LocalDay
    public let text: String
    public let coach: CoachSpeaker

    public init(id: Int, squad: SquadID, day: LocalDay, text: String, coach: CoachSpeaker) {
        (self.id, self.squad, self.day, self.text, self.coach) = (id, squad, day, text, coach)
    }
}

/// The letter a coach the squad let go for another (换教练) left the one that took over (交接信):
/// written once, in the old coach's voice, which every member opens once on 今天 and the new
/// coach's 简历 and 通知 keep.
public struct CoachLetter: Hashable, Sendable, Identifiable {
    public let id: Int
    /// The squad whose coaches changed.
    public let squad: SquadID
    /// The coach that left and wrote it: its 落款.
    public let from: CoachSpeaker
    /// The coach that took over, whom it is to: its 称呼.
    public let recipient: CoachSpeaker
    /// The day it is dated, on the squad's clock.
    public let day: LocalDay
    /// Its body, without the 称呼 or 落款; lines apart by `\n`.
    public let text: String

    public init(id: Int, squad: SquadID, from: CoachSpeaker, to recipient: CoachSpeaker, day: LocalDay, text: String) {
        (self.id, self.squad, self.from, self.recipient, self.day, self.text) = (id, squad, from, recipient, day, text)
    }

    /// Its body's lines, blank ones left out.
    public var lines: [String] {
        text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }
}

/// What the squad's coach said: its newest 战术板 line, its replies to the check-ins asked
/// about, its answers to members' replies to it there, the reader's own morning note, and the
/// letter it was left when it took over.
public struct CoachActivity: Hashable, Sendable {
    public let note: CoachNote?
    public let replies: [CoachReply]
    /// Oldest first.
    public let answers: [CoachAnswer]
    /// The reader's morning note waiting on 今天, if any.
    public let memberNote: CoachMemberNote?
    /// The letter the squad's coach now was left by the one before it, if any.
    public let letter: CoachLetter?

    public init(
        note: CoachNote?, replies: [CoachReply], answers: [CoachAnswer] = [], memberNote: CoachMemberNote? = nil,
        letter: CoachLetter? = nil
    ) {
        self.note = note
        self.replies = replies
        self.answers = answers
        self.memberNote = memberNote
        self.letter = letter
    }
}
