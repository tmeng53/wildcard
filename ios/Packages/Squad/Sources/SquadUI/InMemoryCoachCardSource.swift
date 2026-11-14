import Contracts
import DesignSystemUI
import Foundation
import SquadDomain

/// The coach's cards kept in memory, for previews, UI tests and the sample squad: 毛头's line to
/// the squad, a morning note, a gift and a challenge, as the approved deck shows them.
public actor InMemoryCoachCardSource: CoachCardSource {
    private var stack: [CoachPageCard]
    private var earlier: [CoachPageCard]

    public init(stack: [CoachPageCard], earlier: [CoachPageCard] = []) {
        (self.stack, self.earlier) = (stack, earlier)
    }

    /// The sample deck, its cards from `now`'s morning on; `empty` has everything seen already.
    public static func sample(
        now: Date, coach: CoachSpeaker = CoachSpeaker(id: "xiaohun", name: "毛头"), empty: Bool = false
    )
        -> InMemoryCoachCardSource
    {
        let calendar = Calendar.current
        let morning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? now
        let board = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: now) ?? now
        let day = LocalDay(at: now, in: .current)
        let cards = [
            CoachPageCard(
                kind: .board, id: "board-1", coach: coach, look: coach.id.rawValue, time: board, day: day,
                text: word("这周还差 6 天，周日前补上。")),
            CoachPageCard(
                kind: .note, id: "41", coach: coach, look: coach.id.rawValue, time: morning, day: day,
                text: word("昨天跑完 5 公里还发了图，今天随便动动就行。")),
            CoachPageCard(
                kind: .gift, id: "gift-sheeptowel", coach: coach, look: coach.id.rawValue,
                time: morning.addingTimeInterval(1),
                gift: CoachPageCard.Gift(
                    piece: "gift-sheeptowel", line: word("练完擦汗，别着凉。"))),
            CoachPageCard(
                kind: .challenge, id: "41", coach: coach, look: coach.id.rawValue, time: morning.addingTimeInterval(2),
                day: day,
                challenge: CoachPageCard.Challenge(
                    title: word("拉伸"), amount: 5,
                    unit: word("分钟"),
                    line: word("昨天跑完腿还紧，睡前拉一拉。"))),
        ]
        return empty
            ? InMemoryCoachCardSource(stack: [], earlier: cards.reversed().map { $0.with(isSeen: true) })
            : InMemoryCoachCardSource(stack: cards)
    }

    /// Two coach messages, as an admin would write them (their words are data, in three languages,
    /// as the API sends them): 喜欢外卡吗？, whose answers turn it into a request for a review or a
    /// box for what doesn't work, and a rating of a place with the squad on its stage, 软糖星 and
    /// a box.
    public static func sampleMessages(
        now: Date, coach: CoachSpeaker = CoachSpeaker(id: "xiaohun", name: "毛头")
    ) -> InMemoryCoachCardSource {
        let morning = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? now
        return InMemoryCoachCardSource(stack: [
            CoachPageCard(
                kind: .message, id: "enjoying-wildcard", coach: coach, look: coach.id.rawValue, time: morning,
                message: enjoying),
            CoachPageCard(
                kind: .message, id: "rate-equinox", coach: coach, look: coach.id.rawValue,
                time: morning.addingTimeInterval(60), message: rating),
        ])
    }

    private static func words(_ zhHans: String, _ english: String, _ zhHant: String) -> CatalogNames {
        CatalogNames(simplifiedChinese: zhHans, english: english, traditionalChinese: zhHant)
    }

    /// 喜欢外卡吗？ 喜欢 → 给外卡写个评价？ | 不太喜欢 → 哪里不好用？ with a box sent as 意见反馈.
    private static let enjoying = CoachMessage(cards: [
        CoachMessage.Card(
            path: "", line: words("喜欢外卡吗？", "Enjoying Wildcard?", "喜歡外卡嗎？"),
            buttons: [
                CoachMessage.Button(
                    id: "no", label: words("不太喜欢", "Not really", "不太喜歡"), tap: [.next("no")]),
                CoachMessage.Button(
                    id: "yes", label: words("喜欢", "Yes", "喜歡"), style: .primary, tap: [.next("yes")]),
            ]),
        CoachMessage.Card(
            path: "yes", line: words("给外卡写个评价？", "Leave us a review?", "給外卡寫個評價？"),
            stage: CoachMessage.Stage(cast: .coachAndMe, move: "cheer"),
            buttons: [
                CoachMessage.Button(id: "later", label: words("下次吧", "Later", "下次吧"), tap: [.close]),
                CoachMessage.Button(
                    id: "review", label: words("写评价", "Write one", "寫評價"), style: .primary,
                    tap: [.open("https://apps.apple.com/app/id6826015677?action=write-review"), .close]),
            ], thanks: words("谢谢你！", "Thank you!", "謝謝你！")),
        CoachMessage.Card(
            path: "no", line: words("哪里不好用？", "What isn't working?", "哪裡不好用？"),
            input: CoachMessage.Input(placeholder: words("说说看", "Tell us", "說說看")),
            buttons: [
                CoachMessage.Button(
                    id: "send", label: words("发送", "Send", "發送"), style: .primary,
                    tap: [.feedback("problem"), .close])
            ], thanks: words("收到，谢谢你。", "Got it, thanks.", "收到，謝謝你。")),
    ])

    /// A place to rate, the squad on its stage, with 软糖星 and a box.
    private static let rating = CoachMessage(cards: [
        CoachMessage.Card(
            path: "", line: words("周四去的 Equinox，打个分？", "Rate Thursday's Equinox?", "週四去的 Equinox，打個分？"),
            about: CoachMessage.About(
                icon: "dumbbell.fill", name: words("Equinox", "Equinox", "Equinox"),
                detail: words("小队去了 3 次", "The squad went 3 times", "小隊去了 3 次")),
            stage: CoachMessage.Stage(cast: .coachAndSquad, move: "clap"), stars: true,
            input: CoachMessage.Input(placeholder: words("还想说点什么（可选）", "Anything else (optional)", "還想說點什麼（可選）")),
            buttons: [
                CoachMessage.Button(id: "done", label: words("好了", "Done", "好了"), style: .primary, tap: [.close])
            ],
            thanks: words("收到，谢谢你。", "Got it, thanks.", "收到，謝謝你。"))
    ])

    /// A sample's words in the app's language.
    private static func word(_ key: String) -> String {
        String(copyKey: key, bundle: Bundle.module)
    }

    public func cards(in squad: SquadID) async throws(SquadError) -> CoachPageCards {
        CoachPageCards(stack: stack, earlier: earlier)
    }

    /// 以前 as the API pages it, newest first, a page of 20; 挑战 counts the stack's too.
    public func earlier(in squad: SquadID, from cursor: String?, showing filter: CoachDeck.EarlierFilter)
        async throws(SquadError) -> CoachEarlierCards
    {
        let listed =
            switch filter {
            case .all: earlier
            case .unseen: earlier.filter { !$0.isSeen }
            case .challenges: (stack.reversed() + earlier).filter { $0.kind == .challenge }
            }
        let start =
            cursor.flatMap { after in listed.firstIndex { "\($0.kind.rawValue):\($0.id)" == after } }
            .map { $0 + 1 } ?? 0
        let page = Array(listed.dropFirst(start).prefix(Self.page))
        let more = start + Self.page < listed.count
        return CoachEarlierCards(
            cards: page, next: more ? page.last.map { "\($0.kind.rawValue):\($0.id)" } : nil)
    }

    private static let page = 20

    public func markSeen(_ card: CoachPageCard.Key, in squad: SquadID) async throws(SquadError) {
        if let index = earlier.firstIndex(where: { $0.key == card }) {
            earlier[index] = earlier[index].with(isSeen: true)
        }
        guard let index = stack.firstIndex(where: { $0.key == card }) else { return }
        earlier.insert(stack.remove(at: index).with(isSeen: true), at: 0)
    }

    public func openGift(_ piece: String, worn: Bool) async throws(SquadError) -> CoachPageCard.Gift {
        let opened = { (card: CoachPageCard) -> CoachPageCard.Gift? in
            guard let gift = card.gift, gift.piece == piece else { return nil }
            return gift.isOpen ? gift : CoachPageCard.Gift(piece: piece, line: gift.line, openedAt: .now, worn: worn)
        }
        guard let gift = (stack + earlier).lazy.compactMap(opened).first else { throw .outdated }
        stack = stack.map { $0.gift?.piece == piece ? $0.with(gift: gift) : $0 }
        earlier = earlier.map { $0.gift?.piece == piece ? $0.with(gift: gift) : $0 }
        return gift
    }

    public func answerChallenge(
        _ note: String, in squad: SquadID, with answer: CoachChallengeAnswer, reason: String?
    ) async throws(SquadError) -> CoachChallengeAnswer {
        let isIt = { (card: CoachPageCard) in card.kind == .challenge && card.id == note }
        guard let challenge = (stack + earlier).first(where: isIt)?.challenge else { throw .outdated }
        let answered = challenge.answered(answer)
        stack = stack.map { isIt($0) ? $0.with(challenge: answered) : $0 }
        earlier = earlier.map { isIt($0) ? $0.with(challenge: answered) : $0 }
        return answered.answer ?? answer
    }

    public func answerMessage(_ message: String, in squad: SquadID, on path: String, _ part: CoachMessage.Part)
        async throws(SquadError) -> [String: CoachMessage.Answered]
    {
        let isIt = { (card: CoachPageCard) in card.kind == .message && card.id == message }
        guard let kept = (stack + earlier).first(where: isIt)?.message else { throw .outdated }
        var answered = kept.answered
        let was = answered[path] ?? CoachMessage.Answered()
        answered[path] =
            switch part {
            case .tap(let button): CoachMessage.Answered(tap: was.tap ?? button, stars: was.stars, text: was.text)
            case .stars(let stars): CoachMessage.Answered(tap: was.tap, stars: was.stars ?? stars, text: was.text)
            case .text(let text): CoachMessage.Answered(tap: was.tap, stars: was.stars, text: was.text ?? text)
            }
        let now = kept.with(answered: answered)
        stack = stack.map { isIt($0) ? $0.with(message: now) : $0 }
        earlier = earlier.map { isIt($0) ? $0.with(message: now) : $0 }
        return answered
    }
}
