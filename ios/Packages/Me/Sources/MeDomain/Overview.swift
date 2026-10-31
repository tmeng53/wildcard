import AvatarArt
import AvatarDomain
import Contracts
import Foundation

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

/// The sport a member logged the most 练了 for (最常练), and how many.
public struct MostTrained: Hashable, Sendable {
    public var activity: Activity
    public var checkIns: Int

    public init(activity: Activity, checkIns: Int) {
        (self.activity, self.checkIns) = (activity, checkIns)
    }
}

/// The weekly titles (周奖) a member has won, in all their squads.
public struct TitlesWon: Hashable, Sendable {
    /// The latest title, and how many times they have won it.
    public struct Latest: Hashable, Sendable {
        public var title: String
        public var times: Int

        public init(title: String, times: Int) {
            (self.title, self.times) = (title, times)
        }
    }

    public var count: Int
    /// Nil before the first.
    public var latest: Latest?

    public init(count: Int, latest: Latest?) {
        (self.count, self.latest) = (count, latest)
    }

    public static let none = TitlesWon(count: 0, latest: nil)
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
    /// Nil before the member is in a squad. The app shows one squad, though the API allows three.
    public var squadName: String?
    /// The one daily push at 6pm with the squad's progress.
    public var dailyPushOn: Bool
    /// The number the member picked for their card; nil until they pick one.
    public var jerseyNumber: JerseyNumber?
    /// Their place in their squad, the first to join being 1; nil before they are in one.
    public var squadPlace: Int?
    /// Nil before their first 练了.
    public var mostTrained: MostTrained?
    public var titles: TitlesWon

    public init(
        character: MeCharacter, joinedAt: Date?, counts: LifetimeCounts, week: WeekCount?, squadName: String?,
        dailyPushOn: Bool, jerseyNumber: JerseyNumber? = nil, squadPlace: Int? = nil, mostTrained: MostTrained? = nil,
        titles: TitlesWon = .none
    ) {
        self.character = character
        self.joinedAt = joinedAt
        self.counts = counts
        self.week = week
        self.squadName = squadName
        self.dailyPushOn = dailyPushOn
        self.jerseyNumber = jerseyNumber
        self.squadPlace = squadPlace
        self.mostTrained = mostTrained
        self.titles = titles
    }

    /// The number the card shows: the member's pick, else their place in their squad (the first
    /// to join wears 01); nil with neither.
    public var cardNumber: JerseyNumber? {
        jerseyNumber ?? squadPlace.flatMap { place in try? JerseyNumber(min(place, JerseyNumber.range.upperBound)) }
    }
}
