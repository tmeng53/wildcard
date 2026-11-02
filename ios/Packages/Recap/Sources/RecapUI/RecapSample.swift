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
    /// - Parameters:
    ///   - pending: the AI run hasn't succeeded yet: the titles wait and no page has AI words.
    ///   - missed: the squad fell short of its plans, for the other ending.
    public static func story(pending: Bool = false, missed: Bool = false) -> WeekStory {
        let ready = !pending
        return WeekStory(
            status: pending ? .pending : .ready, squad: SquadID(uuid(9)), squadName: "晨跑五人组",
            week: Week(monday: day(12), sunday: day(18)), scene: .pool, squadmates: squadmates,
            order: [.podium, .titles, .myWeek, .hottest, .meals, .bestDisclaimer, .ending],
            podium: Podium(
                champion: coco, sides: [lin, mia], speech: ready ? "七天五天八点前打卡，闹钟都怕她" : nil,
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
                    .init(day: day(12), kind: .trained("run")), .init(day: day(13), kind: .trained("tennis")),
                    .init(day: day(14), kind: .rest), .init(day: day(15), kind: .trained("strength")),
                    .init(day: day(16), kind: .disclaimer), .init(day: day(17), kind: .trained("yoga")),
                    .init(day: day(18), kind: .rest),
                ], line: ready ? "周二那场网球最有灵魂" : nil, healthyMeals: 3, cheatMeals: 1, reactionsReceived: 12),
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
            ending: missed
                ? Ending(
                    done: 19, plan: 22, headline: ready ? "差一点" : nil, line: ready ? "还差 3 天。下周的腿已经在热身了" : nil,
                    move: ready ? .warmup : nil)
                : Ending(
                    done: 23, plan: 22, headline: ready ? "稳了" : nil, line: ready ? "超额 1 次，多出来那次算利息" : nil,
                    move: ready ? .stack : nil))
    }

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
            ["body": "tuxedo", "top": "warmup-tee", "bottom": "warmup-shorts", "hat": "warmup-headband"]),
        member(
            jay, "阿杰", .shy,
            ["body": "shiba", "top": "warmup-tee", "bottom": "moss-cargo", "hat": "warmup-cap"]),
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
