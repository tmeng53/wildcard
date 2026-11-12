/// A notice we wrote once for every member (群发通知, such as 商店街上新了), told to each on their
/// first open of the app while it runs and then kept in their 通知. Its words are as it says them
/// now, so a fixed typo shows to everyone already told.
public struct Broadcast: Hashable, Sendable {
    /// How the app first shows it.
    public enum Style: Hashable, Sendable {
        /// The home's notice banner.
        case banner
        /// The full-screen celebration; a build without one shows the banner.
        case celebration
    }

    /// A button that opens a place in the app.
    public struct Action: Hashable, Sendable {
        public let label: CatalogNames
        public let destination: AppDestination

        public init(label: CatalogNames, destination: AppDestination) {
            (self.label, self.destination) = (label, destination)
        }
    }

    /// A store, prop or piece it unlocked for the member when they were told it.
    public struct Gift: Hashable, Sendable {
        public let kind: Unlock.Kind
        /// Its id in the art.
        public let id: String

        public init(kind: Unlock.Kind, id: String) {
            (self.kind, self.id) = (kind, id)
        }
    }

    /// A letter from the team (感谢信): opened from an envelope over 今天 in place of its style,
    /// its lines under the member's name, signed 外卡团队, with what the team gave them under it.
    public struct Letter: Hashable, Sendable {
        /// Its words, a line break per line.
        public let lines: CatalogNames
        public let presents: [TeamPresent]

        public init(lines: CatalogNames, presents: [TeamPresent]) {
            (self.lines, self.presents) = (lines, presents)
        }
    }

    /// The same for every member told it, such as `thanksgiving-soon`.
    public let id: String
    public let title: CatalogNames
    /// A muted second line.
    public let body: CatalogNames?
    /// Nil without one, or for a place this build doesn't know.
    public let action: Action?
    public let style: Style
    /// The store's sign, prop or piece drawn beside its words; nil draws its own symbol.
    public let icon: Gift?
    public let gifts: [Gift]
    /// Nil for a notice that is no letter.
    public let letter: Letter?

    public init(
        id: String, title: CatalogNames, body: CatalogNames?, action: Action?, style: Style, icon: Gift? = nil,
        gifts: [Gift], letter: Letter? = nil
    ) {
        (self.id, self.title, self.body, self.action, self.style) = (id, title, body, action, style)
        (self.icon, self.gifts, self.letter) = (icon, gifts, letter)
    }
}

/// Something the team gave the member, which its letter draws: a piece or a team badge, by id.
public enum TeamPresent: Hashable, Sendable {
    case piece(String)
    case badge(String)
}

/// A place in the app: where a notice goes, in 通知, in the home's banner and from its push, the
/// same place for each (`Notice.destination`), and where a broadcast's button opens.
public enum AppDestination: Hashable, Sendable {
    /// 商店街.
    case stores
    /// One store in the 商店街, by its id in the art.
    case store(String)
    /// Where a store, prop or piece that just opened is.
    case unlock(Unlock.Kind, item: String)
    /// 出赛表.
    case schedule
    /// 小队.
    case squad
    /// 教练招聘会, over 今天.
    case coaches
    /// 动态.
    case feed
    /// The squad's 战报 for the week starting `week`.
    case recap(squad: SquadID?, week: LocalDay)
    /// One post's own page.
    case post(CheckInID)
    /// A new 训练, filled from a teammate's that named the member as one it was done with
    /// (一起练): its sport, start, minutes and the teammate.
    case trainAlong(CheckInID)
    /// 今天.
    case today
    /// 今天, where today's pats on the member play again, even ones this phone already showed.
    case pats
    /// 今天, with the coach's morning note (便条) slid up over it again.
    case coachNote(CoachMemberNote)
    /// 今天, with the letter the coach that left wrote the one that took over (交接信) opened over it again.
    case coachLetter(CoachLetter)
    /// 今天, with the coach's newest waiting morning note slid up over it: a tap on its push.
    case waitingCoachNote
    /// 我.
    case profile
    /// 衣橱 in the character editor, trying this piece on (nil: just the editor).
    case wardrobe(piece: String?)
    /// 我's player card turned to its badge board (徽章).
    case badges
    /// 通知, behind the bell on 动态.
    case notices
    /// 今天, with a letter from the team (感谢信) opened over it again.
    indirect case teamLetter(Broadcast)
}

extension Notice {
    /// Where a tap on it goes, from 通知, the home's banner or its push alike.
    public var destination: AppDestination? {
        switch subject {
        // The 6pm push names who patted the member: home, where they pat them again.
        case .dailyProgress: .pats
        case .weeklyAwards(_, let week): .recap(squad: squad, week: week)
        case .sceneMoved: .today
        case .coachReply(let checkIn, _, _, _, _): .post(checkIn)
        case .unlocked(let kind, let item): .unlock(kind, item: item)
        case .comment(_, let checkIn): .post(checkIn)
        case .trainedWith(_, let checkIn): .trainAlong(checkIn)
        case .coachNote(let note): .coachNote(note)
        case .coachLetter(let letter): .coachLetter(letter)
        case .broadcast(let broadcast): broadcast.letter == nil ? broadcast.action?.destination : .teamLetter(broadcast)
        // 小队, whose first card is the weekly goal.
        case .goalSuggestion: .squad
        }
    }
}
