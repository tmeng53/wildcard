import AvatarArt
import AvatarDomain
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

/// What 我 shows: the character, the lifetime counts, the squad and the notification switch.
public struct MeOverview: Hashable, Sendable {
    public var character: MeCharacter
    /// When the member signed up: the day on their character's ticket. Nil before they first
    /// saved a profile.
    public var joinedAt: Date?
    public var counts: LifetimeCounts
    /// Nil before the member is in a squad. The app shows one squad, though the API allows three.
    public var squadName: String?
    /// The one daily push at 6pm with the squad's progress.
    public var dailyPushOn: Bool

    public init(
        character: MeCharacter, joinedAt: Date?, counts: LifetimeCounts, squadName: String?, dailyPushOn: Bool
    ) {
        self.character = character
        self.joinedAt = joinedAt
        self.counts = counts
        self.squadName = squadName
        self.dailyPushOn = dailyPushOn
    }
}
