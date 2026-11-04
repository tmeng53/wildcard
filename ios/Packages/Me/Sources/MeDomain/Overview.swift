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
    /// Every weekly title they won, and the one they wear (徽章板).
    public var board: TitleBoard
    /// The training days in the member's 每周模板, for 设置's row; nil when it didn't load.
    public var templateDays: Int?
    /// The stores, props and pieces the member unlocked by training, which the character editor
    /// opens.
    public var unlocks: [Unlock]
    /// The pieces still locked, which the editor shows as 「？」 boxes.
    public var lockedPieces: [LockedPiece]

    public init(
        character: MeCharacter, joinedAt: Date?, counts: LifetimeCounts, week: WeekCount?, squadName: String?,
        dailyPushOn: Bool, jerseyNumber: JerseyNumber? = nil, squadPlace: Int? = nil, board: TitleBoard = .empty,
        templateDays: Int? = nil, unlocks: [Unlock] = [], lockedPieces: [LockedPiece] = []
    ) {
        self.character = character
        self.joinedAt = joinedAt
        self.counts = counts
        self.week = week
        self.squadName = squadName
        self.dailyPushOn = dailyPushOn
        self.jerseyNumber = jerseyNumber
        self.squadPlace = squadPlace
        self.board = board
        self.templateDays = templateDays
        self.unlocks = unlocks
        self.lockedPieces = lockedPieces
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
    /// 本周 x/y; nil when it isn't known (a squadmate's, or no plan this week).
    public var week: WeekCount?
    public var board: TitleBoard

    public init(
        character: MeCharacter, number: JerseyNumber?, squadName: String?, joinedAt: Date?, counts: LifetimeCounts,
        week: WeekCount?, board: TitleBoard
    ) {
        self.character = character
        self.number = number
        self.squadName = squadName
        self.joinedAt = joinedAt
        self.counts = counts
        self.week = week
        self.board = board
    }

    /// The number a card shows: the member's pick, else their place in their squad (the first to
    /// join wears 01); nil with neither.
    public static func number(picked: JerseyNumber?, place: Int?) -> JerseyNumber? {
        picked ?? place.flatMap { place in try? JerseyNumber(min(place, JerseyNumber.range.upperBound)) }
    }
}
