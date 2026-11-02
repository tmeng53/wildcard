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
    /// 128 days trained, 3 of 5 this week and the approved board's seven titles, ten won in all.
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
                board: .sample,
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

    public func equip(_ title: String?) async throws(MeError) -> TitleBoard {
        if failsSaving { throw .unavailable }
        current.board.worn = title ?? current.board.titles.first?.title
        return current.board
    }

    public func deleteAccount(_ confirmation: DeletionConfirmation) async throws(MeError) {
        if failsSaving { throw .unavailable }
    }
}

/// Squadmates' cards kept in memory, for the sample squad: every teammate shows the same sample
/// card and board under their own character.
public struct InMemorySquadmateCards: SquadmateCards {
    private let characters: @Sendable (MemberID) -> MeCharacter?

    /// `characters` gives the character the home already shows for a teammate.
    public init(characters: @escaping @Sendable (MemberID) -> MeCharacter? = { _ in nil }) {
        self.characters = characters
    }

    public func card(of member: MemberID, in squad: SquadID) async throws(MeError) -> PlayerCardFace {
        PlayerCardFace(
            character: characters(member)
                ?? MeCharacter(
                    nickname: Bundle.module.inAppLanguage.localizedString(forKey: "阿杰", value: nil, table: nil),
                    outfit: PlaceholderCharacter.lifter, persona: .deadpan),
            number: try? JerseyNumber(7), squadName: nil,
            joinedAt: Date(timeIntervalSince1970: 1_792_756_800),
            counts: LifetimeCounts(trainedDays: 42, healthyMeals: 18, cheatMeals: 5, disclaimers: 4), week: nil,
            board: .sample)
    }
}

extension TitleBoard {
    /// The approved badge board's titles, in its order, wearing the latest as the API does
    /// before one is equipped.
    static let sample = TitleBoard(titles: sampleTitles, worn: sampleTitles.first?.title)

    private static let sampleTitles: [BoardTitle] = [
        title("早八战神", "shield", "track", "sun.max.fill", weeks: ["2026-10-26": "连着五天七点前打卡。"]),
        title(
            "冷面杀手", "hexagon", "gym", "snowflake",
            weeks: ["2026-10-19": "练完一句话不说，表情比杠铃还沉。", "2026-10-12": "一整周没发一个表情。"]),
        title("请假条艺术家", "circle", "pool", "doc.text.fill", weeks: ["2026-10-05": "请假条写成了连载。"]),
        title("沙拉守门员", "scallop", "tennis", "leaf.fill", weeks: ["2026-09-28": "五顿健康餐，一顿没破。"]),
        title(
            "对自己很好奖", "circle", "climbing", "heart.fill",
            weeks: ["2026-09-21": "累了就休息，睡够八小时。", "2026-09-14": "按时吃饭。", "2026-09-07": "给自己放了个假。"]),
        title("周三限定", "hexagon", "pool", "bolt.fill", weeks: ["2026-08-31": "只在周三出现，一出现就是十公里。"]),
        title("深夜举铁人", "shield", "gym", "moon.fill", weeks: ["2026-08-24": "晚上十一点还在卧推。"]),
    ]

    private static func title(
        _ key: String, _ shape: String, _ colour: String, _ glyph: String, weeks: KeyValuePairs<String, String>
    ) -> BoardTitle {
        let bundle = Bundle.module.inAppLanguage
        return BoardTitle(
            title: bundle.localizedString(forKey: key, value: nil, table: nil),
            badge: TitleBadge(shape: shape, colour: colour, glyph: glyph),
            weeks: weeks.compactMap { day, speech in
                (try? LocalDay(day)).map {
                    BoardTitle.Week(
                        weekStart: $0, speech: bundle.localizedString(forKey: speech, value: nil, table: nil))
                }
            })
    }
}
