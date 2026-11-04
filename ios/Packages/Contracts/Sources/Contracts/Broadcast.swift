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

    /// The same for every member told it, such as `thanksgiving-soon`.
    public let id: String
    public let title: CatalogNames
    /// A muted second line.
    public let body: CatalogNames?
    /// Nil without one, or for a place this build doesn't know.
    public let action: Action?
    public let style: Style
    public let gifts: [Gift]

    public init(
        id: String, title: CatalogNames, body: CatalogNames?, action: Action?, style: Style, gifts: [Gift]
    ) {
        (self.id, self.title, self.body, self.action, self.style, self.gifts) = (id, title, body, action, style, gifts)
    }
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
    /// 动态.
    case feed
    /// The squad's 战报 for the week starting `week`.
    case recap(squad: SquadID?, week: LocalDay)
    /// One post's own page.
    case post(CheckInID)
    /// 今天.
    case today
    /// 我.
    case profile
}

extension Notice {
    /// Where a tap on it goes, from 通知, the home's banner or its push alike.
    public var destination: AppDestination? {
        switch subject {
        case .dailyProgress: .feed
        case .weeklyAwards(_, let week): .recap(squad: squad, week: week)
        case .sceneMoved: .today
        case .coachReply(let checkIn, _, _, _, _): .post(checkIn)
        case .unlocked(let kind, let item): .unlock(kind, item: item)
        case .comment(_, let checkIn): .post(checkIn)
        case .broadcast(let broadcast): broadcast.action?.destination
        }
    }
}
