import Contracts
import DesignSystemUI
import Foundation
import SquadDomain

/// The coach's cards kept in memory, for previews, UI tests and the sample squad: 毛头's line to
/// the squad, a morning note, a gift, a challenge and a reply, as the approved deck shows them.
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
        let post = CheckInID(UUID(uuidString: "c0000000-0000-4000-8000-000000000001") ?? UUID())
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
            CoachPageCard(
                kind: .reply, id: "reply-1", coach: coach, look: coach.id.rawValue,
                time: morning.addingTimeInterval(4 * 3600 + 40 * 60),
                text: word("配速比上周快了，不错。"), checkIn: post),
        ]
        return empty
            ? InMemoryCoachCardSource(stack: [], earlier: cards.reversed())
            : InMemoryCoachCardSource(stack: cards)
    }

    /// A sample's words in the app's language.
    private static func word(_ key: String) -> String {
        Bundle.module.inAppLanguage.localizedString(forKey: key, value: nil, table: nil)
    }

    public func cards(in squad: SquadID) async throws(SquadError) -> CoachPageCards {
        CoachPageCards(stack: stack, earlier: earlier)
    }

    public func markSeen(_ card: CoachPageCard.Key, in squad: SquadID) async throws(SquadError) {
        guard let index = stack.firstIndex(where: { $0.key == card }) else { return }
        earlier.insert(stack.remove(at: index), at: 0)
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
        _ note: String, in squad: SquadID, with answer: CoachChallengeAnswer
    ) async throws(SquadError) -> CoachChallengeAnswer {
        let isIt = { (card: CoachPageCard) in card.kind == .challenge && card.id == note }
        guard let challenge = (stack + earlier).first(where: isIt)?.challenge else { throw .outdated }
        let answered = challenge.answered(answer)
        stack = stack.map { isIt($0) ? $0.with(challenge: answered) : $0 }
        earlier = earlier.map { isIt($0) ? $0.with(challenge: answered) : $0 }
        return answered.answer ?? answer
    }
}
