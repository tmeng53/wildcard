import AvatarArt
import Foundation
import MeDomain

/// A member kept in memory, for previews, UI tests and builds before the API client is wired.
public actor InMemoryMeService: MeService {
    private var current: MeOverview
    private let failsSaving: Bool
    public private(set) var deleted = false

    /// `failsSaving` refuses every switch, so UI tests can see one flip back.
    public init(overview: MeOverview, failsSaving: Bool = false) {
        current = overview
        self.failsSaving = failsSaving
    }

    /// The member the screens are reviewed against: 小林 of 周三不练腿俱乐部, 128 days trained.
    public static func sample(failsSaving: Bool = false) -> InMemoryMeService {
        InMemoryMeService(
            overview: MeOverview(
                character: MeCharacter(
                    nickname: Bundle.module.localizedString(forKey: "小林", value: nil, table: nil),
                    outfit: PlaceholderCharacter.lifter, persona: .energetic),
                counts: LifetimeCounts(trainedDays: 128, healthyMeals: 46, cheatMeals: 12, disclaimers: 9),
                squadName: Bundle.module.localizedString(forKey: "周三不练腿俱乐部", value: nil, table: nil),
                dailyPushOn: true),
            failsSaving: failsSaving)
    }

    public func overview() async throws(MeError) -> MeOverview {
        current
    }

    public func save(_ character: MeCharacter) async throws(MeError) {
        if failsSaving { throw .unavailable }
        current.character = character
    }

    public func setDailyPush(_ isOn: Bool) async throws(MeError) {
        if failsSaving { throw .unavailable }
        current.dailyPushOn = isOn
    }

    public func deleteAccount(_ confirmation: DeletionConfirmation) async throws(MeError) {
        if failsSaving { throw .unavailable }
        deleted = true
    }
}
