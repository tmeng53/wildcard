import Foundation

/// A coach message (教练消息卡, Tracy 2026-11-12): a card admins write, said by the squad's coach
/// with no model writing it. It is one template filled by data: a line, and each other slot only
/// when filled. Its buttons' steps are data too, so where a button goes changes without a
/// release. A button may turn the card into another card of the same message (`next`), so a
/// message is a small tree of cards, each named by its path: `` for the first, else the ids of
/// the buttons tapped to reach it, joined by `.`.
public struct CoachMessage: Hashable, Sendable {
    /// One card of the message.
    public struct Card: Hashable, Sendable {
        public let path: String
        /// What the coach says, big.
        public let line: CatalogNames
        public let body: CatalogNames?
        public let about: About?
        public let stage: Stage
        /// Five 软糖星 to tap (`stars` answers).
        public let stars: Bool
        /// A box to type in (`text` answers), with what it says while empty.
        public let input: Input?
        /// Up to 3 buttons, left to right.
        public let buttons: [Button]
        /// What the card says once a button closes it.
        public let thanks: CatalogNames?

        public init(
            path: String, line: CatalogNames, body: CatalogNames? = nil, about: About? = nil,
            stage: Stage = Stage(), stars: Bool = false, input: Input? = nil, buttons: [Button] = [],
            thanks: CatalogNames? = nil
        ) {
            (self.path, self.line, self.body, self.about, self.stage) = (path, line, body, about, stage)
            (self.stars, self.input, self.buttons, self.thanks) = (stars, input, buttons, thanks)
        }
    }

    /// What a card is about: a symbol, a name and a line under it.
    public struct About: Hashable, Sendable {
        /// An SF Symbol.
        public let icon: String?
        public let name: CatalogNames
        public let detail: CatalogNames?

        public init(icon: String? = nil, name: CatalogNames, detail: CatalogNames? = nil) {
            (self.icon, self.name, self.detail) = (icon, name, detail)
        }
    }

    /// Who stands with the coach on a card's stage.
    public enum Cast: Hashable, Sendable {
        /// The coach alone.
        case coach
        /// The coach and the reader.
        case coachAndMe
        /// The coach and the whole squad, in two rows of four past four.
        case coachAndSquad
        /// The coach and these members, by id.
        case members([MemberID])
    }

    /// The picture on top: who stands with the coach, the move it plays and the scene behind.
    public struct Stage: Hashable, Sendable {
        public let cast: Cast
        /// The coach's move by the art's id; nil plays its idle.
        public let move: String?
        /// The scene behind them by id; nil is the squad's scene this week.
        public let scene: String?

        public init(cast: Cast = .coachAndMe, move: String? = nil, scene: String? = nil) {
            (self.cast, self.move, self.scene) = (cast, move, scene)
        }
    }

    public struct Input: Hashable, Sendable {
        public let placeholder: CatalogNames?

        public init(placeholder: CatalogNames? = nil) {
            self.placeholder = placeholder
        }
    }

    /// `primary` is graphite, `outline` white with a hairline, `plain` words only.
    public enum ButtonStyle: String, Hashable, Sendable {
        case primary, outline, plain
    }

    public struct Button: Hashable, Sendable, Identifiable {
        public let id: String
        public let label: CatalogNames
        /// An SF Symbol before the words.
        public let icon: String?
        public let style: ButtonStyle
        /// What a tap does, in order.
        public let tap: [Step]

        public init(id: String, label: CatalogNames, icon: String? = nil, style: ButtonStyle = .outline, tap: [Step]) {
            (self.id, self.label, self.icon, self.style, self.tap) = (id, label, icon, style, tap)
        }

        /// The card's words go as 意见反馈 on this tap, so it needs something typed.
        public var sendsFeedback: Bool { tap.contains { if case .feedback = $0 { true } else { false } } }
    }

    /// One step of a tap. A step this build doesn't know is left out when read.
    public enum Step: Hashable, Sendable {
        /// Opens a place in the app by its address, or an https page.
        case open(String)
        /// Sends what was typed in the card's box as 意见反馈, as this kind (`problem` or `idea`).
        case feedback(String)
        /// Folds the card to its thanks.
        case close
        /// Turns the card into the card at this path.
        case next(String)
    }

    /// What the reader did on one card; the first answer to each part stands.
    public struct Answered: Hashable, Sendable {
        public let tap: String?
        public let stars: Int?
        public let text: String?

        public init(tap: String? = nil, stars: Int? = nil, text: String? = nil) {
            (self.tap, self.stars, self.text) = (tap, stars, text)
        }
    }

    /// One part of an answer to one card.
    public enum Part: Hashable, Sendable {
        case tap(String)
        case stars(Int)
        case text(String)
    }

    /// Where the reader is in the message: on a card, or on a card a tap closed (its thanks).
    public enum Place: Hashable, Sendable {
        case card(String)
        case closed(String)

        public var path: String {
            switch self {
            case .card(let path), .closed(let path): path
            }
        }
    }

    /// The most characters a typed answer keeps; the API checks the same.
    public static let textLimit = 500

    /// What was typed as it is sent: trimmed and cut to `textLimit`, nil when nothing is left.
    public static func text(_ typed: String) -> String? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(textLimit))
    }

    /// Every card, the first (path ``) first.
    public let cards: [Card]
    /// What the reader did on each card so far, by path.
    public let answered: [String: Answered]

    public init(cards: [Card], answered: [String: Answered] = [:]) {
        (self.cards, self.answered) = (cards, answered)
    }

    public func card(at path: String) -> Card? { cards.first { $0.path == path } }

    /// The same message with these answers, as the server sent them back.
    public func with(answered: [String: Answered]) -> CoachMessage {
        CoachMessage(cards: cards, answered: answered)
    }

    /// Where the reader's taps so far took them: from the first card, each tapped button's `next`
    /// turns to its card and its `close` folds that card to its thanks; a card with no tap yet, or
    /// whose tap did neither, is where they are. The same on every phone, since the server keeps
    /// the taps.
    public var place: Place {
        var path = ""
        // A tree three cards deep at most; the bound only guards against a loop.
        for _ in 0...cards.count {
            guard let card = card(at: path), let tapped = answered[path]?.tap,
                let button = card.buttons.first(where: { $0.id == tapped })
            else { return .card(path) }
            if let next = button.tap.lazy.compactMap({ step -> String? in
                if case .next(let next) = step { next } else { nil }
            }).first, self.card(at: next) != nil {
                path = next
                continue
            }
            return button.tap.contains(.close) ? .closed(path) : .card(path)
        }
        return .card(path)
    }
}
