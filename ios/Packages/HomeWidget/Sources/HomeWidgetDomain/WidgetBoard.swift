import CheckInDomain
import Contracts
import Foundation

/// What the home screen widgets show, from the home the app or the widget last loaded: my week
/// (我的一周, the small widget) and the squad's week and today (小队今天, the medium one), each
/// counted the way the home's squad card counts them.
public struct WidgetBoard: Hashable, Sendable {
    /// Where one member's day stands, as their ring shows it.
    public enum MateStatus: Hashable, Sendable {
        /// 练了 or a 请假条 today: the ring closes.
        case checkedIn
        /// A rest day in their plan: the grey ring with the moon.
        case restDay
        case notYet
    }

    /// One member's head on the medium widget, with today's ring.
    public struct Mate: Hashable, Sendable {
        public let member: MemberID
        /// Nil before they made their character.
        public let look: CharacterLook?
        public let status: MateStatus
        public let isMe: Bool
    }

    /// My day, which the board is for.
    public let day: LocalDay
    /// My week, Monday to Sunday.
    public let week: WeekRecord
    /// 我的一周 x/y: days I trained over the days I planned.
    public let mine: WeekCount
    /// Whether I trained today, posted a 请假条 or neither.
    public let myStatus: TrainingStatus
    public let squadName: String
    /// 小队本周目标 x/y 次: every 训练 sent to the squad, as the squad card shows it.
    public let squad: WeekCount
    /// Everyone in the squad, me included, in the home's order: who checked in first.
    public let mates: [Mate]
    /// The squad's coach, when it has one.
    public let coach: CoachID?
    /// The coach has a card I haven't seen: its phone's ink dot.
    public let coachHasNews: Bool

    /// - Parameters:
    ///   - home: the home as last loaded; moved on to `day` when it is from an earlier one.
    ///   - day: my day now, on my profile's clock (`Home.timeZone`).
    public init(home: Home, day: LocalDay, coach: CoachID? = nil, coachHasNews: Bool = false) {
        // A copy read on an earlier day of mine says nothing about anyone's today yet. Each
        // teammate's row is their own today on their own clock, so a teammate behind me in time
        // reads an earlier day in a fresh copy too, and counts as the squad card counts them.
        let stale = home.today.members.first { $0.member == home.member }.map { $0.day < day } ?? false
        let home = home.rolled(to: day)
        self.day = day
        week = home.week(on: day)
        mine = home.today.myWeek.week
        myStatus = home.squadSees(on: day)
        squadName = home.squad.name
        squad = home.today.squadWeek
        mates = home.today.members.map { mate in
            let isMe = mate.member == home.member
            let status: MateStatus =
                stale && !isMe
                ? .notYet
                : mate.training != .notCheckedIn ? .checkedIn : mate.plannedRest ? .restDay : .notYet
            return Mate(member: mate.member, look: mate.character?.look, status: status, isMe: isMe)
        }
        self.coach = coach
        self.coachHasNews = coachHasNews
    }

    /// How many in the squad checked in today: 今天 x/y.
    public var checkedInToday: Int { mates.count { $0.status == .checkedIn } }

    /// Where a tap on 我的一周 goes: straight to 打卡 until I check in today, else 今天.
    public var weekLink: WidgetLink { myStatus == .notCheckedIn ? .checkIn : .today }

    /// When the widgets should look again: in half an hour, or at my midnight if that comes
    /// first, when the board moves on to a new day.
    public static func nextLook(after now: Date, in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let soon = now.addingTimeInterval(refreshInterval)
        guard let midnight = calendar.nextDate(after: now, matching: DateComponents(hour: 0), matchingPolicy: .nextTime)
        else { return soon }
        return min(soon, midnight)
    }

    /// How often a widget reads the squad again. WidgetKit gives a widget a few dozen reloads a
    /// day; every half hour keeps well inside that.
    public static let refreshInterval: TimeInterval = 30 * 60
}

/// What a widget shows: the board, or why there is none.
public enum WidgetState: Hashable, Sendable {
    case board(WidgetBoard)
    /// Signed in but in no squad yet.
    case noSquad
    /// Nobody signed in on this phone.
    case signedOut
    /// Couldn't read the squad and has no copy of it: offline before its first read, or the
    /// phone not yet unlocked since it restarted. Read again soon.
    case unavailable

    /// How long until the widget reads again when it has no board.
    public static let retryInterval: TimeInterval = 15 * 60
}
