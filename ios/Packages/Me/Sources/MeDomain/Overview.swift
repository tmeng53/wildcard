import AvatarArt
import AvatarDomain
import Contracts
import Foundation
import ScheduleDomain

/// Everything the member ever checked in, by kind. Counts only go up.
public struct LifetimeCounts: Hashable, Sendable {
    /// Days with a 练了: several on one day count once.
    public var trainedDays: Int
    public var healthyMeals: Int
    public var cheatMeals: Int
    public var disclaimers: Int

    public init(trainedDays: Int, healthyMeals: Int, cheatMeals: Int, disclaimers: Int) {
        (self.trainedDays, self.healthyMeals, self.cheatMeals, self.disclaimers) =
            (trainedDays, healthyMeals, cheatMeals, disclaimers)
    }

    public static let zero = LifetimeCounts(trainedDays: 0, healthyMeals: 0, cheatMeals: 0, disclaimers: 0)
}

/// The member's character as 我 shows it: how it looks and moves, and its name.
public struct MeCharacter: Hashable, Sendable {
    public var nickname: String
    public var outfit: Outfit
    public var persona: Persona

    public init(nickname: String, outfit: Outfit, persona: Persona) {
        (self.nickname, self.outfit, self.persona) = (nickname, outfit, persona)
    }
}

/// This week at a glance, for 我's 出赛表 tile: the week's number and each day's mark.
public struct WeekGlance: Hashable, Sendable {
    /// How a day of the week looks on the tile.
    public enum Mark: Hashable, Sendable {
        /// A 练了 was posted that day.
        case trained
        /// A training day in the plan with no 练了 (yet, or not that day: never marked as missed).
        case planned
        /// A rest day in the plan.
        case rest
    }

    /// One day, Monday first.
    public struct Day: Hashable, Sendable {
        public var mark: Mark
        public var isToday: Bool

        public init(mark: Mark, isToday: Bool) {
            (self.mark, self.isToday) = (mark, isToday)
        }
    }

    /// The week's number on the 出赛表, the week the member joined being 1 (W45).
    public var number: Int
    /// Seven days, Monday first.
    public var days: [Day]

    public init(number: Int, days: [Day]) {
        (self.number, self.days) = (number, days)
    }

    /// The days left in the week, today included (这周还有 N 天); nil when no day is today.
    public var daysLeft: Int? {
        days.firstIndex(where: \.isToday).map { days.count - $0 }
    }

    /// The week as the plan has it and the days that had a 练了: a 练了 marks its day whatever
    /// the plan said.
    public init(number: Int, plan: [PlanDay], trainedDays: Set<Int>, today: Int?) {
        self.number = number
        days = plan.enumerated().map { index, day in
            let mark: Mark =
                if trainedDays.contains(index) {
                    .trained
                } else if case .rest = day {
                    .rest
                } else {
                    .planned
                }
            return Day(mark: mark, isToday: index == today)
        }
    }
}

/// What 我 shows: the character, the player card's records, this week, the squad and the
/// notification switch.
public struct MeOverview: Hashable, Sendable {
    public var character: MeCharacter
    /// When the member signed up: the day on their character's ticket. Nil before they first
    /// saved a profile.
    public var joinedAt: Date?
    public var counts: LifetimeCounts
    /// 本周 x/y; nil while the member has no plan for the week.
    public var week: WeekCount?
    /// This week's days for the 出赛表 tile; nil when they couldn't be read (the tile then shows
    /// the count alone).
    public var weekGlance: WeekGlance?
    /// The last weeks of training for 训练记录; nil when they couldn't be read (the heatmap is
    /// left out).
    public var record: TrainingRecord?
    /// Nil before the member is in a squad. The app shows one squad, though the API allows three.
    public var squadName: String?
    /// The one daily push at 6pm with the squad's progress.
    public var dailyPushOn: Bool
    /// The coach's pushes (教练消息): its morning note and its replies, all silent.
    public var coachPushOn: Bool
    /// The number the member picked for their card; nil until they pick one.
    public var jerseyNumber: JerseyNumber?
    /// Their place in their squad, the first to join being 1; nil before they are in one.
    public var squadPlace: Int?
    /// Every weekly title they won, and the one they wear (徽章板).
    public var board: TitleBoard
    /// The stores, props and pieces the member unlocked by training, which the character editor
    /// opens.
    public var unlocks: [Unlock]
    /// The 商店街 as the server works it out for the member, which the editor draws; nil for the
    /// starter street.
    public var stock: StreetStock?
    /// The unlocked pieces the member claimed (领取) into their wardrobe.
    public var claimed: Set<String>

    public init(
        character: MeCharacter, joinedAt: Date?, counts: LifetimeCounts, week: WeekCount?, squadName: String?,
        dailyPushOn: Bool, coachPushOn: Bool = true, jerseyNumber: JerseyNumber? = nil, squadPlace: Int? = nil,
        board: TitleBoard = .empty,
        unlocks: [Unlock] = [], stock: StreetStock? = nil, claimed: Set<String> = [], weekGlance: WeekGlance? = nil,
        record: TrainingRecord? = nil
    ) {
        self.weekGlance = weekGlance
        self.record = record
        self.character = character
        self.joinedAt = joinedAt
        self.counts = counts
        self.week = week
        self.squadName = squadName
        self.dailyPushOn = dailyPushOn
        self.coachPushOn = coachPushOn
        self.jerseyNumber = jerseyNumber
        self.squadPlace = squadPlace
        self.board = board
        self.unlocks = unlocks
        self.stock = stock
        self.claimed = claimed
    }

    /// The number on the member's card.
    public var cardNumber: JerseyNumber? { PlayerCardFace.number(picked: jerseyNumber, place: squadPlace) }

    /// The member's own player card.
    public var card: PlayerCardFace {
        PlayerCardFace(
            character: character, number: cardNumber,
            squadName: squadName, joinedAt: joinedAt, counts: counts, week: week, board: board)
    }
}

/// What a player card shows, front and back: the member's own on 我, or a squadmate's.
public struct PlayerCardFace: Hashable, Sendable {
    public var character: MeCharacter
    /// The number on it; nil with neither a pick nor a place in a squad.
    public var number: JerseyNumber?
    public var squadName: String?
    /// When they signed up: the year on the card.
    public var joinedAt: Date?
    public var counts: LifetimeCounts
    /// 本周 x/y, theirs for a squadmate; nil when it isn't known (an older server, or no plan this week).
    public var week: WeekCount?
    public var board: TitleBoard
    /// A squadmate's 出赛表 this week, on their card's back; nil on the member's own card and from
    /// an older server.
    public var schedule: MateSchedule?

    public init(
        character: MeCharacter, number: JerseyNumber?, squadName: String?, joinedAt: Date?, counts: LifetimeCounts,
        week: WeekCount?, board: TitleBoard, schedule: MateSchedule? = nil
    ) {
        self.character = character
        self.number = number
        self.squadName = squadName
        self.joinedAt = joinedAt
        self.counts = counts
        self.week = week
        self.board = board
        self.schedule = schedule
    }

    /// The number a card shows: the member's pick, else their place in their squad (the first to
    /// join wears 01); nil with neither.
    public static func number(picked: JerseyNumber?, place: Int?) -> JerseyNumber? {
        picked ?? place.flatMap { place in try? JerseyNumber(min(place, JerseyNumber.range.upperBound)) }
    }
}

/// A squadmate's 出赛表 for this week only, as the back of their card shows it: the plan's seven
/// days, how each went, and the week's 饮食小目标.
public struct MateSchedule: Hashable, Sendable {
    /// The week's Monday, in their time zone.
    public let weekStart: LocalDay
    /// Seven, Monday first.
    public let days: [PlanDay]
    /// Seven, Monday first.
    public let marks: [DayMark]
    /// Empty when they set none, and then the card says nothing about them.
    public let fuel: [FuelGoal]
    /// The Monday of the week they joined, in their time zone; nil before they saved a profile.
    public let firstWeek: LocalDay?

    public init(
        weekStart: LocalDay, days: [PlanDay], marks: [DayMark], fuel: [FuelGoal], firstWeek: LocalDay?
    ) throws(MeError) {
        guard days.count == WeeklyPlan.dayCount, marks.count == WeeklyPlan.dayCount else { throw .rejected }
        (self.weekStart, self.days, self.marks, self.fuel, self.firstWeek) = (weekStart, days, marks, fuel, firstWeek)
    }

    /// The week's number on the card (W6), the week they joined being W1, as their own 出赛表
    /// counts it on their calendar; W1 without it.
    public var weekNumber: Int {
        firstWeek.map { weekStart.weekNumber(since: $0) } ?? 1
    }
}
