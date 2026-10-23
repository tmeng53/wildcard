import Contracts
import DailyPushDomain
import Foundation

/// The 6pm push the push view is reviewed against, as the server would send it on `now`'s day:
/// 阿杰's squats, 豆豆's 请假条, Leo's salad and 小米's rainy run, two more in 动态, and 小米
/// patted the member. `empty` is the same push on a day nobody has posted.
public enum DailyPushSample {
    public static func push(empty: Bool, now: Date, zone: TimeZone = .current) -> DailyPush? {
        try? DailyPush(event: Data(event(empty: empty, now: now, zone: zone).utf8))
    }

    /// The squad's looks, as the app keeps them for the push.
    public static let looks: [MemberID: CharacterLook] = [
        member(1): CharacterLook(
            persona: "energetic", variants: ["body": "peach", "hair": "curls", "top": "tee", "bottom": "shorts"],
            colors: ["body": "#C68A5E"]),
        member(2): CharacterLook(persona: "drama", variants: ["body": "shiba", "top": "hoodie", "bottom": "shorts"]),
        member(3): CharacterLook(
            persona: "deadpan", variants: ["body": "calico", "top": "tee", "bottom": "greenshorts"]),
        member(4): CharacterLook(
            persona: "showoff", variants: ["body": "peach", "hair": "ponytail", "top": "tank", "bottom": "leggings"]),
    ]

    private static func member(_ number: Int) -> MemberID {
        MemberID(UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", number)) ?? UUID())
    }

    private static func post(_ number: Int) -> String {
        String(format: "10000000-0000-4000-8000-%012d", number)
    }

    private static func event(empty: Bool, now: Date, zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        func at(_ hour: Int, _ minute: Int) -> String {
            let time = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
            return Timestamp(time).description
        }
        let named: [(Int, String?)] = [(0, nil), (1, "阿杰"), (2, "豆豆"), (3, "Leo"), (4, "小米")]
        let members =
            named
            .map { number, name in
                name.map { #"{"id": "\#(member(number))", "name": "\#($0)"}"# } ?? #"{"id": "\#(member(number))"}"#
            }
            .joined(separator: ", ")
        let posts =
            empty
            ? ""
            : """
            {"id": "\(post(1))", "by": 1, "kind": "trained", "sport": "strength", "at": "\(at(17, 42))",
             "text": "深蹲加了 5 公斤，腿在抖", "reactions": [[3, "💪"], [4, "😂"], [2, "💪"]], "reactionCount": 3},
            {"id": "\(post(2))", "by": 2, "kind": "disclaimer", "at": "\(at(16, 10))",
             "text": "腿说今天它请假，我尊重它的决定，明天再说", "reactions": [[1, "😂"]], "reactionCount": 1},
            {"id": "\(post(3))", "by": 3, "kind": "healthyMeal", "at": "\(at(12, 30))",
             "text": "今天的草，吃得很体面", "reactions": [[2, "🤤"], [1, "🤤"]], "reactionCount": 2},
            {"id": "\(post(4))", "by": 4, "kind": "trained", "sport": "run", "at": "\(at(7, 15))",
             "text": "下雨也跑了，鞋已阵亡", "reactions": [], "reactionCount": 0}
            """
        return """
            {"kind": "dailyProgress", "squadTrainedDays": 9, "squadPlannedDays": 16,
             "today": {"members": [\(members)], "posts": [\(posts)], "more": \(empty ? 0 : 2), "pokedBy": [4]}}
            """
    }
}
