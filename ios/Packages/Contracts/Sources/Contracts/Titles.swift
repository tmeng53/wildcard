/// 头衔徽章: the weekly titles a member won in the Sunday 战报, each with the badge the AI picked
/// for it, the one they wear on their player card and beside their name, and their badge board.

/// A title's badge: a shape in a scene's colour with an SF Symbol on it. The API sends each as
/// text and the app keeps them so, so a new glyph needs no app release; what this build can't
/// draw is drawn as its default.
public struct TitleBadge: Hashable, Sendable {
    /// Its shape (`shield`), drawn by `DesignSystemUI`'s `TitleBadgeView`, which draws one it
    /// doesn't know as a circle.
    public var shape: String
    /// The scene whose colour it takes, by the scene's id (`track`); the drawing falls back to the
    /// gym's for one it doesn't know.
    public var colour: String
    /// The SF Symbol's name; the drawing falls back to a star for one this iOS doesn't have.
    public var glyph: String

    public init(shape: String, colour: String, glyph: String) {
        (self.shape, self.colour, self.glyph) = (shape, colour, glyph)
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

        public init(weekStart: LocalDay, speech: String?) {
            (self.weekStart, self.speech) = (weekStart, speech)
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
}

/// Every title a member won, in all their squads, and the one they wear.
public struct TitleBoard: Hashable, Sendable {
    /// The latest won first.
    public var titles: [BoardTitle]
    /// The title worn on the card's front: the one equipped, else the latest won; nil before the
    /// first.
    public var worn: String?

    public init(titles: [BoardTitle], worn: String?) {
        (self.titles, self.worn) = (titles, worn)
    }

    public static let empty = TitleBoard(titles: [], worn: nil)

    /// The worn title with its badge.
    public var wornTitle: WornTitle? {
        titles.first { $0.title == worn }.map { WornTitle(title: $0.title, badge: $0.badge) }
    }

    /// Every title won, counting each repeat: 徽章 on the card's front.
    public var count: Int { titles.reduce(0) { $0 + $1.times } }
}
