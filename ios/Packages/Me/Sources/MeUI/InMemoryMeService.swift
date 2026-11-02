import AvatarArt
import Contracts
import DesignSystemUI
import Foundation
import MeDomain

/// A member kept in memory, for previews, UI tests and builds before the API client is wired.
public actor InMemoryMeService: MeService {
    private var current: MeOverview
    private let failsSaving: Bool

    /// `failsSaving` refuses every switch, so UI tests can see one flip back.
    public init(overview: MeOverview, failsSaving: Bool = false) {
        current = overview
        self.failsSaving = failsSaving
    }

    /// The member the screens are reviewed against: 小林 of 周三不练腿俱乐部, number 22 since 2026,
    /// 128 days trained (most of them runs), 3 of 5 this week and 3 weekly titles.
    public static func sample(failsSaving: Bool = false) -> InMemoryMeService {
        InMemoryMeService(
            overview: MeOverview(
                character: MeCharacter(
                    nickname: Bundle.module.inAppLanguage.localizedString(forKey: "小林", value: nil, table: nil),
                    outfit: PlaceholderCharacter.lifter, persona: .energetic),
                joinedAt: Date(timeIntervalSince1970: 1_792_756_800),  // 2026-10-23, noon UTC
                counts: LifetimeCounts(trainedDays: 128, healthyMeals: 46, cheatMeals: 12, disclaimers: 9),
                week: WeekCount(trainedDays: 3, plannedDays: 5),
                squadName: Bundle.module.inAppLanguage.localizedString(forKey: "周三不练腿俱乐部", value: nil, table: nil),
                dailyPushOn: true,
                jerseyNumber: try? JerseyNumber(22), squadPlace: 2,
                mostTrained: MostTrained(activity: .sport("run"), checkIns: 34),
                titles: TitlesWon(
                    count: 3,
                    latest: TitlesWon.Latest(
                        title: Bundle.module.inAppLanguage.localizedString(forKey: "早八战神", value: nil, table: nil),
                        times: 2)),
                templateDays: 5),
            failsSaving: failsSaving)
    }

    public func overview() async throws(MeError) -> MeOverview {
        current
    }

    public func save(_ character: MeCharacter) async throws(MeError) {
        if failsSaving { throw .unavailable }
        current.character = character
    }

    public func save(jerseyNumber: JerseyNumber) async throws(MeError) {
        if failsSaving { throw .unavailable }
        current.jerseyNumber = jerseyNumber
    }

    public func setDailyPush(_ isOn: Bool) async throws(MeError) {
        if failsSaving { throw .unavailable }
        current.dailyPushOn = isOn
    }

    public func deleteAccount(_ confirmation: DeletionConfirmation) async throws(MeError) {
        if failsSaving { throw .unavailable }
    }
}
