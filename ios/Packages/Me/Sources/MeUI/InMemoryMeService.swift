import AvatarArt
import AvatarDomain
import Contracts
import DesignSystemUI
import Foundation
import MeDomain
import ScheduleDomain

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
    public static func sample(
        failsSaving: Bool = false, unlocks: [Unlock] = [], stock: StreetStock? = nil, gifts: [String] = []
    ) -> InMemoryMeService {
        InMemoryMeService(
            overview: MeOverview(
                character: MeCharacter(
                    nickname: String(copyKey: "小林", bundle: Bundle.module),
                    outfit: PlaceholderCharacter.lifter, persona: .energetic),
                joinedAt: Date(timeIntervalSince1970: 1_792_756_800),  // 2026-10-23, noon UTC
                counts: LifetimeCounts(trainedDays: 128, healthyMeals: 46, cheatMeals: 12, disclaimers: 9),
                week: WeekCount(trainedDays: 3, plannedDays: 5),
                squadName: String(copyKey: "周三不练腿俱乐部", bundle: Bundle.module),
                dailyPushOn: true,
                jerseyNumber: try? JerseyNumber(22), squadPlace: 2,
                board: .sample,
                unlocks: unlocks, stock: stock, gifts: gifts,
                // 3 of 5: Monday, Wednesday and today (Thursday) trained, Tuesday and Sunday off.
                weekGlance: WeekGlance(
                    number: 3,
                    plan: [.train(nil), .rest, .train(nil), .train(nil), .train(nil), .train(nil), .rest],
                    trainedDays: [0, 2, 3], today: 3),
                record: sampleRecord,
                streaks: CardStreaks(training: 5, meals: 12)),
            failsSaving: failsSaving)
    }

    /// The sample's 训练记录: 21 weeks to Thursday 2026-11-05, a 练了 on about three days in five
    /// at a run of lengths, the same every launch.
    static var sampleRecord: TrainingRecord {
        let today = (try? LocalDay(year: 2026, month: 11, day: 5)) ?? LocalDay(at: .now, in: .current)
        let sports: [Sport] = ["run", "swim", "strength", "yoga", "tennis"]
        let lengths: [Int?] = [20, 45, 60, nil, 30, 90, 40]
        var seed = 11
        var trainings: [TrainingDay] = []
        var day = TrainingRecord.firstDay(today: today)
        var index = 0
        while day <= today {
            seed = (seed * 9301 + 49297) % 233_280
            if seed % 5 < 3 {
                trainings.append(
                    TrainingDay(
                        id: CheckInID(
                            UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index)) ?? UUID()),
                        day: day, activity: .sport(sports[index % sports.count]),
                        minutes: lengths[index % lengths.count]))
            }
            index += 1
            day = day.adding(days: 1)
        }
        return TrainingRecord(today: today, trainings: trainings)
    }

    /// The sample's 外卡记录, the approved design's numbers: 27 days, mostly at 7pm and on
    /// Tuesdays, a 6-day run, 32 days of 健康餐 to today, and Coco as the best partner.
    static var sampleRecords: WildcardRecords {
        func day(_ month: Int, _ day: Int) -> LocalDay {
            (try? LocalDay(year: 2026, month: month, day: day)) ?? LocalDay(at: .now, in: .current)
        }
        let coco = RecordMate(
            member: MemberID(UUID(uuidString: "00000000-0000-0000-0000-00000000c0c0") ?? UUID()),
            character: MeCharacter(
                nickname: "Coco",
                outfit: Outfit([
                    "body": "lop", "eyes": "happy", "mouth": "cat", "cheeks": "rosy", "hat": "warmup-headband",
                    "top": "warmup-hoodie", "bottom": "warmup-joggers", "shoes": "warmup-canvas",
                ]), persona: .shy))
        var hours = Array(repeating: 0, count: 24)
        for (hour, count) in [6: 2, 7: 3, 8: 3, 9: 1, 12: 2, 13: 1, 17: 2, 18: 4, 19: 7, 20: 5, 21: 3, 22: 1] {
            hours[hour] = count
        }
        return WildcardRecords(
            trainedDays: 27, minutes: 1290, longestMinutes: 95,
            longestStreak: .init(days: 6, first: day(10, 20), last: day(10, 25)),
            mealStreak: .init(days: 32, first: day(10, 6), last: day(11, 5)),
            // No training run going: the sample shows a broken streak's tile without 现在连续.
            currentMealStreak: .init(days: 32, first: day(10, 6), last: day(11, 5)),
            hours: hours, weekdays: [5, 6, 3, 4, 4, 3, 2],
            sports: [
                .init(activity: .sport("run"), days: 11), .init(activity: .sport("strength"), days: 8),
                .init(activity: .sport("tennis"), days: 5),
            ],
            sportCount: 5,
            squad: SquadStanding(
                partner: .init(mate: coco, count: 12),
                cheersReceived: .init(count: 86, top: .init(mate: coco, count: 23)),
                cheersGiven: .init(count: 41, top: .init(mate: coco, count: 14)),
                firsts: [.latestTrainer, .topSport]))
    }

    public func records() async throws(MeError) -> WildcardRecords {
        Self.sampleRecords
    }

    public func overview() async throws(MeError) -> MeOverview {
        current
    }

    /// The member's 商店街 changes, as a switch or a new store would change it on the server.
    public func set(stock: StreetStock) {
        current.stock = stock
    }

    public func save(_ character: MeCharacter) async throws(MeError) {
        if failsSaving { throw .unavailable }
        current.character = character
    }

    public func save(jerseyNumber: JerseyNumber) async throws(MeError) {
        if failsSaving { throw .unavailable }
        current.jerseyNumber = jerseyNumber
    }

    public func save(birthday: Birthday?) async throws(MeError) {
        if failsSaving { throw .unavailable }
        current.birthday = birthday
    }

    public func setDailyPush(_ isOn: Bool) async throws(MeError) {
        if failsSaving { throw .unavailable }
        current.dailyPushOn = isOn
    }

    public func setCoachPush(_ isOn: Bool) async throws(MeError) {
        if failsSaving { throw .unavailable }
        current.coachPushOn = isOn
    }

    public func setTeammatePush(_ isOn: Bool) async throws(MeError) {
        if failsSaving { throw .unavailable }
        current.teammatePushOn = isOn
    }

    public func equip(_ wearable: Wearable?) async throws(MeError) -> TitleBoard {
        if failsSaving { throw .unavailable }
        current.board.wear(wearable)
        return current.board
    }

    public func claim(piece: String) async throws(MeError) {
        if failsSaving { throw .unavailable }
        current.claimed.insert(piece)
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
                    nickname: String(copyKey: "阿杰", bundle: Bundle.module),
                    outfit: PlaceholderCharacter.lifter, persona: .deadpan),
            number: try? JerseyNumber(7), squadName: nil,
            counts: LifetimeCounts(trainedDays: 42, healthyMeals: 18, cheatMeals: 5, disclaimers: 4),
            week: WeekCount(trainedDays: 3, plannedDays: 5),
            board: .sample, schedule: .sample(weekOf: LocalDay(at: Date(), in: .current)),
            // Their meals broke: only the training 外卡 shows.
            streaks: CardStreaks(training: 12, meals: 0))
    }
}

extension MateSchedule {
    /// The approved card back's week (E1): 网球 and 跑步 trained, a 请假条 on Thursday, 力量训练
    /// trained on Friday, 网球 still to come, and two 饮食小目标, in their third week (W3).
    static func sample(weekOf day: LocalDay) -> MateSchedule? {
        let tennis = PlanDay.train(.sport("tennis"))
        let run = PlanDay.train(.sport("run"))
        let strength = PlanDay.train(.sport("strength"))
        return try? MateSchedule(
            weekStart: day.weekStart,
            days: [tennis, .rest, run, tennis, strength, tennis, .rest],
            marks: [
                .trained([.sport("tennis")]), .none, .trained([.sport("run")]), .disclaimer,
                .trained([.sport("strength")]), .none, .none,
            ],
            fuel: [.suggested(.veggies), .suggested(.lessBubbleTea)],
            firstWeek: day.weekStart.adding(days: -14), today: day)
    }
}

extension TitleBoard {
    /// The approved badge board's titles, in its order, wearing the latest as the API does
    /// before one is equipped, and a badge the team gave just now, NEW until it is opened.
    static let sample = TitleBoard(
        titles: sampleTitles, worn: sampleTitles.first?.title,
        teamBadges: [
            TeamBadge(
                id: "idea-king",
                name: CatalogNames(simplifiedChinese: "点子王", english: "Idea King", traditionalChinese: "點子王"),
                line: CatalogNames(
                    simplifiedChinese: "首席点子官", english: "Chief Idea Officer",
                    traditionalChinese: "首席點子官"),
                glyph: "lightbulb.fill", tone: "#F2B33D", times: 1, latestAt: Date())
        ])

    private static let sampleTitles: [BoardTitle] = [
        title("早八战神", "shield", "track", "sun.max.fill", weeks: ["2026-10-26": "连着五天七点前打卡。"]),
        title(
            "冷面杀手", "hexagon", "ski", "snowflake",
            weeks: ["2026-10-19": "练完一句话不说，表情比杠铃还沉。", "2026-10-12": "一整周没发一个表情。"]),
        title("请假条艺术家", "circle", "lavender", "doc.text.fill", weeks: ["2026-10-05": "请假条写成了连载。"]),
        title("沙拉守门员", "scallop", "mint", "leaf.fill", weeks: ["2026-09-28": "五顿健康餐，一顿没破。"]),
        title(
            "对自己很好奖", "circle", "honey", "heart.fill",
            weeks: ["2026-09-21": "累了就休息，睡够八小时。", "2026-09-14": "按时吃饭。", "2026-09-07": "给自己放了个假。"]),
        title("周三限定", "hexagon", "pool", "figure.pool.swim", weeks: ["2026-08-31": "只在周三出现，一出现就是十公里。"]),
        title(
            "深夜举铁人", "shield", "graphite", "figure.strengthtraining.traditional", weeks: ["2026-08-24": "晚上十一点还在卧推。"]),
    ]

    /// The tones the badge catalog sends with its colours.
    private static let sampleTones = [
        "track": "#E65345", "ski": "#16384D", "lavender": "#9062DE", "mint": "#278C5E", "honey": "#A0760E",
        "pool": "#079BB8", "graphite": "#1F2128",
    ]

    private static func title(
        _ key: String, _ shape: String, _ colour: String, _ glyph: String, weeks: KeyValuePairs<String, String>
    ) -> BoardTitle {
        let bundle = Bundle.module
        return BoardTitle(
            title: String(copyKey: key, bundle: bundle),
            badge: TitleBadge(shape: shape, colour: colour, tone: sampleTones[colour], glyph: glyph),
            weeks: weeks.compactMap { day, speech in
                (try? LocalDay(day)).map {
                    BoardTitle.Week(
                        weekStart: $0, speech: String(copyKey: speech, bundle: bundle),
                        squadName: String(copyKey: "周三不练腿俱乐部", bundle: bundle))
                }
            })
    }
}
