import Foundation

/// 头衔徽章: the weekly titles a member won in the Sunday 战报, each with the badge the AI picked
/// for it, the one they wear on their player card and beside their name, and their badge board.

/// A title's badge: a shape in a scene's colour with an SF Symbol on it. The API sends each as
/// text and the app keeps them so, so a new glyph needs no app release; what this build can't
/// draw is drawn as its default.
public struct TitleBadge: Hashable, Sendable {
    /// Its shape (`shield`), drawn by `DesignSystemUI`'s `TitleBadgeView`, which draws one it
    /// doesn't know as a circle.
    public var shape: String
    /// Its colour's id in the badge catalog (`track`).
    public var colour: String
    /// That colour as `#RRGGBB`, what the badge is painted in; nil from servers before tones,
    /// when the drawing takes the scene of `colour`'s id, else the gym's.
    public var tone: String?
    /// The SF Symbol's name; the drawing falls back to a star for one this iOS doesn't have.
    public var glyph: String

    public init(shape: String, colour: String, tone: String? = nil, glyph: String) {
        (self.shape, self.colour, self.tone, self.glyph) = (shape, colour, tone, glyph)
    }

    /// The badge of a title won before titles came with one.
    public static let plain = TitleBadge(shape: "circle", colour: "gym", glyph: "star.fill")
}

/// The title a member wears, with its badge.
public struct WornTitle: Hashable, Sendable {
    public var title: String
    public var badge: TitleBadge

    public init(title: String, badge: TitleBadge) {
        (self.title, self.badge) = (title, badge)
    }
}

/// One title on a member's badge board (徽章板): its words, the badge it was last won with, and
/// every week it was won, the latest first.
public struct BoardTitle: Hashable, Sendable, Identifiable {
    /// A week the title was won.
    public struct Week: Hashable, Sendable {
        /// The Monday of that week.
        public var weekStart: LocalDay
        /// Its award line (颁奖词) that week; nil on a squadmate's card for a week won in another
        /// squad.
        public var speech: String?
        /// The name of the squad it was won in, as that week's 战报 froze it; nil for a week won
        /// before 战报 froze, and on a squadmate's card for a week won in another squad.
        public var squadName: String?

        public init(weekStart: LocalDay, speech: String?, squadName: String? = nil) {
            (self.weekStart, self.speech, self.squadName) = (weekStart, speech, squadName)
        }
    }

    public var title: String
    public var badge: TitleBadge
    /// Never empty: the latest first.
    public var weeks: [Week]

    public init(title: String, badge: TitleBadge, weeks: [Week]) {
        (self.title, self.badge, self.weeks) = (title, badge, weeks)
    }

    public var id: String { title }
    /// How many times it was won: ×N on the board.
    public var times: Int { weeks.count }
    /// The award line shown on its detail: the latest one there is.
    public var latestSpeech: String? { weeks.lazy.compactMap(\.speech).first }
    /// The squad of the week `latestSpeech` comes from, by its name that week; nil when that week
    /// names none.
    public var latestSquadName: String? { weeks.first { $0.speech != nil }?.squadName }
}

/// A dedicated badge the Wildcard team gave the member (捉虫队 for a bug we confirmed, say): never
/// a weekly title's badge, drawn as a ticket apart from them, held as many times as it was given.
/// Its name, glyph and tone come from the server, so a new one needs no app release.
public struct TeamBadge: Hashable, Sendable, Identifiable {
    /// Its catalog id (`bug-hunter`).
    public var id: String
    public var name: CatalogNames
    /// The SF Symbol's name; the drawing falls back to a star for one this iOS doesn't have.
    public var glyph: String
    /// Its colour as `#RRGGBB`.
    public var tone: String
    /// How many times it was given: ×N on the board.
    public var times: Int
    /// When it was given the last time; nil from servers before it, and on the sample squad.
    public var latestAt: Date?

    public init(id: String, name: CatalogNames, glyph: String, tone: String, times: Int, latestAt: Date? = nil) {
        (self.id, self.name, self.glyph, self.tone, self.times, self.latestAt) = (
            id, name, glyph, tone, times, latestAt
        )
    }

    /// Its badge as a title's is drawn: a ticket in its own colour.
    public var badge: TitleBadge { TitleBadge(shape: "ticket", colour: id, tone: tone, glyph: glyph) }
}

/// What a member may wear on their card's front and beside their name: one of their weekly
/// titles, by its words, or a badge the team gave them, by its id.
public enum Wearable: Hashable, Sendable {
    case title(String)
    case teamBadge(String)
}

/// Every title a member won, in all their squads, the one they wear, and the team's badges.
public struct TitleBoard: Hashable, Sendable {
    /// The latest won first.
    public var titles: [BoardTitle]
    /// The title worn on the card's front: the one equipped, else the latest won; nil before the
    /// first, and while a team badge is worn.
    public var worn: String?
    /// The team's badges, the latest got first.
    public var teamBadges: [TeamBadge]
    /// The team badge worn on the card's front instead of a title, by its id; nil unless the
    /// member chose one.
    public var wornTeamBadge: String?

    public init(titles: [BoardTitle], worn: String?, teamBadges: [TeamBadge] = [], wornTeamBadge: String? = nil) {
        (self.titles, self.worn, self.teamBadges, self.wornTeamBadge) = (titles, worn, teamBadges, wornTeamBadge)
    }

    public static let empty = TitleBoard(titles: [], worn: nil)

    /// What is worn on the card's front, with its badge: the team badge chosen, named in the first
    /// of `languages` there are words in, else the title worn.
    public func wornTitle(in languages: [String]) -> WornTitle? {
        if let badge = teamBadges.first(where: { $0.id == wornTeamBadge }) {
            return WornTitle(title: badge.name.localized(in: languages), badge: badge.badge)
        }
        return titles.first { $0.title == worn }.map { WornTitle(title: $0.title, badge: $0.badge) }
    }

    /// Whether `wearable` is what the card's front wears.
    public func wears(_ wearable: Wearable) -> Bool {
        switch wearable {
        case .title(let title): wornTeamBadge == nil && worn == title
        case .teamBadge(let id): wornTeamBadge == id
        }
    }

    /// Wears `wearable` at once, as the API will once it saves; nil wears the latest title won
    /// again.
    public mutating func wear(_ wearable: Wearable?) {
        switch wearable {
        case .title(let title): (worn, wornTeamBadge) = (title, nil)
        case .teamBadge(let id): (worn, wornTeamBadge) = (nil, id)
        case nil: (worn, wornTeamBadge) = (titles.first?.title, nil)
        }
    }

    /// Every badge held, each title's and the team's, counting each repeat: 徽章 on the card's
    /// front.
    public var count: Int { titles.reduce(0) { $0 + $1.times } + teamBadges.reduce(0) { $0 + $1.times } }
}
