import Contracts
import DesignSystem
import Foundation

/// One squad's week as the Sunday 战报 tells it, for the member reading it. The weekly AI run
/// fills it once per squad-week: the facts (who finished their plan, counts, days, check-ins)
/// come from the database, the words and moves from the model. Every AI part is optional, so a
/// story still `pending` on the model is the same shape with those left out.
public struct WeekStory: Hashable, Sendable {
    public enum Status: Hashable, Sendable {
        /// The awards are in.
        case ready
        /// The week is over but the AI run hasn't written the titles yet: their page says the
        /// organizers ran out of money, with a button to nudge them; every other page plays.
        case pending
    }

    public let status: Status
    public let squad: SquadID
    public let squadName: String
    /// Monday to Sunday.
    public let week: Week
    /// The page order the AI picked, or nil to use `PageID.defaultOrder`.
    public let order: [PageID]?
    public let podium: Podium?
    public let titles: [MemberTitles]
    public let myWeek: MyWeek?
    public let hottest: Hottest?
    public let meals: Meals?
    public let bestDisclaimer: BestDisclaimer?
    public let ending: Ending?

    public init(
        status: Status, squad: SquadID, squadName: String, week: Week, order: [PageID]? = nil,
        podium: Podium? = nil, titles: [MemberTitles] = [], myWeek: MyWeek? = nil, hottest: Hottest? = nil,
        meals: Meals? = nil, bestDisclaimer: BestDisclaimer? = nil, ending: Ending? = nil
    ) {
        self.status = status
        self.squad = squad
        self.squadName = squadName
        self.week = week
        self.order = order
        self.podium = podium
        self.titles = titles
        self.myWeek = myWeek
        self.hottest = hottest
        self.meals = meals
        self.bestDisclaimer = bestDisclaimer
        self.ending = ending
    }

    /// The pages to play, in order. A page whose data is missing is left out, and the ending,
    /// when there is one, closes the story. While the titles are pending, the pending page takes their place
    /// and every other page plays as usual.
    public var pages: [StoryPage] {
        var ids = (order ?? PageID.defaultOrder).filter { $0 != .ending }
        ids = ids.reduce(into: []) { kept, id in if !kept.contains(id) { kept.append(id) } }
        ids.append(.ending)
        return ids.compactMap { id in
            id == .titles && status == .pending ? .pending : page(id)
        }
    }

    private func page(_ id: PageID) -> StoryPage? {
        switch id {
        case .podium: podium.map(StoryPage.podium)
        case .titles: titles.isEmpty ? nil : .titles(titles)
        case .myWeek: myWeek.map(StoryPage.myWeek)
        case .hottest: hottest.map(StoryPage.hottest)
        case .meals: meals.map(StoryPage.meals)
        case .bestDisclaimer: bestDisclaimer.map(StoryPage.bestDisclaimer)
        case .ending: ending.map(StoryPage.ending)
        }
    }

    /// The first title each member won, for the podium's steps.
    public func firstTitle(of member: MemberID) -> String? {
        titles.first { $0.member == member }?.titles.first?.title
    }

    /// Everyone the story names, in the order they appear: the podium, then the titles, then
    /// whoever else shows up. The scene's lineups (meals, the ending) stand them in this order.
    public var cast: [MemberID] {
        var ids: [MemberID] = []
        func add(_ id: MemberID) { if !ids.contains(id) { ids.append(id) } }
        if let podium { ([podium.champion] + podium.sides).forEach(add) }
        titles.map(\.member).forEach(add)
        meals?.eaters.map(\.member).forEach(add)
        bestDisclaimer.map { add($0.author) }
        return ids
    }
}

/// A Monday-to-Sunday week.
public struct Week: Hashable, Sendable {
    public let monday: LocalDay
    public let sunday: LocalDay

    public init(monday: LocalDay, sunday: LocalDay) {
        self.monday = monday
        self.sunday = sunday
    }
}

/// Which page, as the API names it in `order`.
public enum PageID: String, CaseIterable, Hashable, Sendable {
    case podium, titles, myWeek, hottest, meals, bestDisclaimer, ending

    /// The order when the AI didn't pick one: the awards first, the ending last.
    public static let defaultOrder: [PageID] = [.podium, .titles, .myWeek, .hottest, .meals, .bestDisclaimer, .ending]
}

/// One full-screen page of the story.
public enum StoryPage: Hashable, Sendable {
    /// The titles while the AI run is late: the organizers are out of money, nudge them.
    case pending
    case podium(Podium)
    case titles([MemberTitles])
    case myWeek(MyWeek)
    case hottest(Hottest)
    case meals(Meals)
    case bestDisclaimer(BestDisclaimer)
    case ending(Ending)
}

/// 领奖台: everyone who finished their plan, the crown winner in the middle. No ranks.
public struct Podium: Hashable, Sendable {
    public let champion: MemberID
    /// Up to two others who finished their plan, left then right.
    public let sides: [MemberID]
    /// The 颁奖词 for the champion.
    public let speech: String?
    public let championMove: AwardMove?
    public let sideMove: AwardMove?

    public init(
        champion: MemberID, sides: [MemberID], speech: String? = nil, championMove: AwardMove? = nil,
        sideMove: AwardMove? = nil
    ) {
        self.champion = champion
        self.sides = Array(sides.prefix(2))
        self.speech = speech
        self.championMove = championMove
        self.sideMove = sideMove
    }
}

/// 本周头衔: one member's titles, each with its 颁奖词 and move.
public struct MemberTitles: Hashable, Sendable {
    public struct Title: Hashable, Sendable {
        public let title: String
        public let speech: String?
        public let move: AwardMove?

        public init(title: String, speech: String? = nil, move: AwardMove? = nil) {
            self.title = title
            self.speech = speech
            self.move = move
        }
    }

    public let member: MemberID
    /// 1 to 3, the one the story shows first.
    public let titles: [Title]

    public init(member: MemberID, titles: [Title]) {
        self.member = member
        self.titles = titles
    }
}

/// 你的一周: the reader's own week, Monday first.
public struct MyWeek: Hashable, Sendable {
    public let plan: Int
    public let days: [Day]
    public let line: String?
    public let healthyMeals: Int
    public let cheatMeals: Int
    public let reactionsReceived: Int

    public struct Day: Hashable, Sendable {
        public let day: LocalDay
        public let kind: DayKind

        public init(day: LocalDay, kind: DayKind) {
            self.day = day
            self.kind = kind
        }
    }

    public init(
        plan: Int, days: [Day], line: String? = nil, healthyMeals: Int, cheatMeals: Int, reactionsReceived: Int
    ) {
        self.plan = plan
        self.days = days
        self.line = line
        self.healthyMeals = healthyMeals
        self.cheatMeals = cheatMeals
        self.reactionsReceived = reactionsReceived
    }

    /// Days trained: what the big number counts up to.
    public var trainedDays: Int {
        days.count { if case .trained = $0.kind { true } else { false } }
    }
}

/// What a day of the week was.
public enum DayKind: Hashable, Sendable {
    /// Trained; the sport is that day's main one, nil for 其他.
    case trained(Sport?)
    /// A planned rest day.
    case rest
    /// A 请假条.
    case disclaimer
    /// Nothing checked in.
    case none
}

/// 你最火的一条: the reader's check-in with the most reactions, as it was when the awards ran.
public struct Hottest: Hashable, Sendable {
    public let checkIn: CheckInID
    public let day: LocalDay
    public let kind: CheckInKind
    public let sport: Sport?
    /// The caption, or a 请假条's text.
    public let words: String?
    /// Signed URLs, the cover first.
    public let photos: [URL]
    public let reactions: [ReactionCount]
    public let line: String?
    public let move: AwardMove?

    public init(
        checkIn: CheckInID, day: LocalDay, kind: CheckInKind, sport: Sport? = nil, words: String? = nil,
        photos: [URL] = [], reactions: [ReactionCount], line: String? = nil, move: AwardMove? = nil
    ) {
        self.checkIn = checkIn
        self.day = day
        self.kind = kind
        self.sport = sport
        self.words = words
        self.photos = photos
        self.reactions = reactions
        self.line = line
        self.move = move
    }
}

/// How many teammates reacted with one emoji. Any emoji is a reaction, so it stays a string.
public struct ReactionCount: Hashable, Sendable {
    public let emoji: String
    public let count: Int

    public init(emoji: String, count: Int) {
        self.emoji = emoji
        self.count = count
    }
}

/// 吃了: the squad's meals. Never a judgment of food or bodies.
public struct Meals: Hashable, Sendable {
    public let healthy: Int
    public let cheat: Int
    public let eaters: [Eater]
    public let line: String?

    public struct Eater: Hashable, Sendable {
        public let member: MemberID
        /// What they logged more of.
        public let more: Meal

        public init(member: MemberID, more: Meal) {
            self.member = member
            self.more = more
        }
    }

    public enum Meal: Hashable, Sendable {
        case healthy, cheat
    }

    public init(healthy: Int, cheat: Int, eaters: [Eater], line: String? = nil) {
        self.healthy = healthy
        self.cheat = cheat
        self.eaters = eaters
        self.line = line
    }
}

/// 最佳请假条: the 请假条 with the most reactions.
public struct BestDisclaimer: Hashable, Sendable {
    public let checkIn: CheckInID
    public let author: MemberID
    public let text: String
    public let reactions: Int
    /// The author acting the note out.
    public let authorMove: AwardMove?
    /// How two teammates react.
    public let squadMove: AwardMove?

    public init(
        checkIn: CheckInID, author: MemberID, text: String, reactions: Int, authorMove: AwardMove? = nil,
        squadMove: AwardMove? = nil
    ) {
        self.checkIn = checkIn
        self.author = author
        self.text = text
        self.reactions = reactions
        self.authorMove = authorMove
        self.squadMove = squadMove
    }
}

/// 这一周: the squad's training days against its plans. Never red, never guilt.
public struct Ending: Hashable, Sendable {
    public let done: Int
    public let plan: Int
    /// ≤ 4 characters, such as 稳了 or 差一点.
    public let headline: String?
    public let line: String?
    public let move: AwardMove?

    public init(done: Int, plan: Int, headline: String? = nil, line: String? = nil, move: AwardMove? = nil) {
        self.done = max(done, 0)
        self.plan = max(plan, 0)
        self.headline = headline
        self.line = line
        self.move = move
    }

    /// The squad trained at least as many days as it planned.
    public var isHit: Bool { done >= plan }

    /// Days still missing, for the line without the AI: 「还差 3 次」.
    public var shortBy: Int { max(plan - done, 0) }

    /// How full the bar is, from 0 to 1.
    public var fraction: Double { plan > 0 ? min(Double(done) / Double(plan), 1) : 1 }
}
