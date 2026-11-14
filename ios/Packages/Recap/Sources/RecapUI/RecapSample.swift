#if os(iOS)
import AvatarArt
import AvatarDomain
import Contracts
import DesignSystem
import Foundation
import RecapDomain

/// A filled-in week for the demo squad, as the API would freeze it and the weekly AI run fill
/// it: what the app plays without a backend, and what the UI tests screenshot. Its words stand in
/// for the API's, which arrive already in the reader's language.
public enum RecapSample {
    /// 全队运动总结: each member's days, the reader's matching 你的一周.
    private static let squadWeek = SquadWeek(members: [
        week(coco, "run", "run", nil, "run", "strength", "run", nil),
        week(lin, "tennis", nil, "tennis", nil, "tennis", nil, nil),
        week(mia, "run", nil, "run", "yoga", nil, "run", nil),
        week(jay, nil, "strength", nil, nil, nil, nil, "yoga"),
        week(reader, "run", "tennis", nil, "strength", nil, "yoga", nil),
    ])

    /// A member's week for 全队运动总结: each day's sport, nil for a day they didn't train.
    /// Every trained day logged 40 minutes, but Coco's long Saturday run.
    private static func week(_ member: MemberID, _ sports: Sport?...) -> SquadWeek.Member {
        SquadWeek.Member(
            member: member, days: sports.map { $0.map(DayKind.trained) ?? .none },
            minutes: sports.enumerated().map { index, sport in
                sport == nil ? nil : member == coco && index == 5 ? 95 : 40
            },
            reactionsReceived: sports.count { $0 != nil } * 3)
    }

    /// - Parameters:
    ///   - pending: the AI run hasn't succeeded yet: the titles wait and no page has AI words.
    ///   - stuck: with `pending`, a try failed, so the organizers are out of funds; otherwise
    ///     the titles are only on their way.
    ///   - missed: the squad fell short of its plans, for the other ending.
    ///   - monday: the week, the sample week of 10.12 unless another is asked for, as 往期战报 does.
    ///   - scene: where the squad trained that week.
    public static func story(
        pending: Bool = false, stuck: Bool = true, missed: Bool = false, monday: LocalDay? = nil,
        scene: SceneTheme = .pool
    ) -> WeekStory {
        let ready = !pending
        return WeekStory(
            status: pending ? .pending : .ready, stuck: pending && stuck, squad: SquadID(uuid(9)), squadName: "晨跑五人组",
            week: week(from: monday ?? day(12)), scene: scene, squadmates: squadmates,
            order: [.podium, .titles, .myWeek, .squadWeek, .hottest, .meals, .bestDisclaimer, .ending],
            podium: Podium(
                champion: coco, sides: [lin, mia], planDone: [coco, mia], speech: ready ? "七天五天八点前打卡，闹钟都怕她" : nil,
                championMove: ready ? .pose : nil, sideMove: ready ? .pump : nil),
            titles: ready
                ? [
                    title(coco, "早八战神", "七天五天八点前打卡，闹钟都怕她", .pose),
                    title(lin, "网球场钉子户", "三次打卡都在同一块场地，球场该发他会员卡", .pump),
                    title(mia, "雨中狠人", "周三下雨照跑 5 公里，伞都没带", .stretch),
                    title(jay, "请假条文豪", "两张请假条，篇篇有人笑死", .laugh),
                    title(reader, "稳定输出", "4 天，不多不少，比上班打卡还准", .wave),
                ] : [],
            myWeek: RecapDomain.MyWeek(
                plan: 5,
                days: [
                    .init(day: day(12), kind: .trained("run"), minutes: 35),
                    .init(day: day(13), kind: .trained("tennis"), minutes: 90),
                    .init(day: day(14), kind: .rest), .init(day: day(15), kind: .trained("strength"), minutes: 50),
                    .init(day: day(16), kind: .disclaimer), .init(day: day(17), kind: .trained("yoga")),
                    .init(day: day(18), kind: .rest),
                ], line: ready ? "周二那场网球最有灵魂" : nil, healthyMeals: 3, cheatMeals: 1, reactionsReceived: 12),
            squadWeek: squadWeek,
            hottest: Hottest(
                checkIn: CheckInID(uuid(20)), day: day(15), kind: .trained, sport: "run", words: "晨跑 8 公里，腿还在",
                reactions: [
                    ReactionCount(emoji: "💪", count: 5),
                    ReactionCount(emoji: "😂", count: 3),
                    ReactionCount(emoji: "❤️", count: 2),
                ], line: ready ? "五个人给你加油，腿替你谢谢大家" : nil, move: ready ? .pose : nil),
            meals: Meals(
                healthy: 14, cheat: 5,
                eaters: [
                    .init(member: lin, more: .healthy), .init(member: mia, more: .cheat),
                    .init(member: coco, more: .healthy), .init(member: jay, more: .cheat),
                    .init(member: reader, more: .healthy),
                ], line: ready ? "健康餐赢了，汉堡不服" : nil),
            bestDisclaimer: BestDisclaimer(
                checkIn: CheckInID(uuid(21)), author: jay, text: "教练说要循序渐进，我今天进的是被窝。", reactions: 6,
                authorMove: ready ? .flat : nil, squadMove: ready ? .laugh : nil),
            menu: menu, places: places,
            ending: ending(missed: missed, ready: ready))
    }

    /// 这一周: over the plan, or just short of it.
    private static func ending(missed: Bool, ready: Bool) -> Ending {
        missed
            ? Ending(
                done: 19, plan: 22, headline: ready ? "差一点" : nil, line: ready ? "下周的腿已经在热身了" : nil,
                move: ready ? .warmup : nil)
            : Ending(
                done: 23, plan: 22, headline: ready ? "稳了" : nil, line: ready ? "超额 1 次，多出来那次算利息" : nil,
                move: ready ? .stack : nil)
    }

    /// 小队菜单: the week's three best 卡价比, the API's order.
    private static let menu = [
        MenuDish(
            checkIn: CheckInID(uuid(30)), author: mia, day: day(13), healthy: 5, tasty: 5, caption: "牛油果碗",
            place: place("Sweetgreen", 40.7397, -73.9897)),
        MenuDish(checkIn: CheckInID(uuid(31)), author: lin, day: day(15), healthy: 4, tasty: 5, caption: "刺身拼盘"),
        MenuDish(checkIn: CheckInID(uuid(32)), author: coco, day: day(16), healthy: 4, tasty: 4, caption: "番茄炒蛋"),
    ]

    /// Where the squad trained: the gym most, and the park for the first time.
    private static let places = [
        PlaceWeek(
            key: "apple:I1A2B3C4D5E6F", place: place("Equinox Flatiron", 40.7404, -73.9914), firstTime: false,
            visits: [
                .init(member: lin, day: day(12)), .init(member: lin, day: day(14)), .init(member: lin, day: day(16)),
                .init(member: mia, day: day(13)), .init(member: mia, day: day(15)), .init(member: coco, day: day(13)),
                .init(member: coco, day: day(17)), .init(member: reader, day: day(15)),
                .init(member: reader, day: day(17)),
            ]),
        PlaceWeek(
            key: "apple:I9F8E7D6C5B4A", place: place("Hudson River Park", 40.7267, -74.0110), firstTime: true,
            visits: [
                .init(member: jay, day: day(14)), .init(member: mia, day: day(16)), .init(member: coco, day: day(17)),
            ]),
    ]

    private static func place(_ name: String, _ latitude: Double, _ longitude: Double) -> Place {
        guard let place = try? Place(name: name, latitude: latitude, longitude: longitude) else {
            fatalError("The sample squad's places are valid")
        }
        return place
    }

    private static func week(from monday: LocalDay) -> Week {
        Week(monday: monday, sunday: monday.adding(days: 6))
    }

    /// The sample squad's 往期战报: the sample week and the three before it, the latest first.
    static let pastWeeks = (0..<4).map { day(12).adding(days: -7 * $0) }
    /// Where the sample squad trained each of those weeks.
    static let pastScenes: [SceneTheme] = [.pool, .track, .gym, .tennis]

    /// The demo squad on the pool scene, read by 我.
    public static let cast = StoryCast(story: story(), viewer: reader)

    /// The demo squad as the story keeps it.
    private static let squadmates = [
        member(
            coco, "Coco", .energetic,
            [
                "body": "peach", "hair": "curls", "eyes": "happy", "brows": "arched", "mouth": "grin",
                "cheeks": "flushed",
                "top": "nolook-jersey", "bottom": "warmup-shorts",
            ]),
        member(
            lin, "小林", .showoff,
            [
                "body": "peach", "hair": "wolf", "eyes": "sharp", "brows": "bold", "mouth": "smirk",
                "top": "warmup-tank",
                "bottom": "warmup-shorts",
            ]),
        member(
            mia, "Mia", .drama,
            [
                "body": "tuxedo", "cheeks": "rosy", "top": "warmup-tee", "bottom": "warmup-shorts",
                "hat": "warmup-headband",
            ]),
        member(
            jay, "阿杰", .shy,
            ["body": "shiba", "cheeks": "rosy", "top": "warmup-tee", "bottom": "moss-cargo", "hat": "warmup-cap"]),
        member(
            reader, "我", .deadpan,
            [
                "body": "peach", "hair": "long", "eyes": "sleepy", "brows": "soft", "mouth": "smile",
                "cheeks": "rosy",
                "glasses": "square", "top": "warmup-hoodie", "bottom": "warmup-leggings",
            ]),
    ]

    private static let coco = MemberID(uuid(1))
    private static let lin = MemberID(uuid(2))
    private static let mia = MemberID(uuid(3))
    private static let jay = MemberID(uuid(4))
    private static let reader = MemberID(uuid(5))

    private static func member(_ id: MemberID, _ nickname: String, _ persona: Persona, _ look: [Slot: String])
        -> Squadmate
    {
        guard let name = try? Nickname(nickname) else { fatalError("The sample squad's nicknames are valid") }
        return Squadmate(
            member: id,
            character: MemberCharacter(nickname: name, look: CharacterLook(outfit: Outfit(look), persona: persona)))
    }

    private static func title(_ member: MemberID, _ title: String, _ speech: String, _ move: AwardMove) -> MemberTitles
    {
        MemberTitles(member: member, titles: [.init(title: title, speech: speech, move: move)])
    }

    private static func uuid(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number)) ?? UUID()
    }

    /// A day of the sample week, 2026-10-12 to 18.
    private static func day(_ number: Int) -> LocalDay {
        guard let day = try? LocalDay(year: 2026, month: 10, day: number) else {
            fatalError("The sample week's days are valid dates")
        }
        return day
    }
}
#endif
