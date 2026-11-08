#if os(iOS)
import AvatarDomain
import Contracts
import DesignSystem
import DesignSystemUI
import SquadDomain
import SwiftUI

/// Where the coach page's buttons go, and what it borrows from the wardrobe, passed in by the app.
public struct CoachDeckPlaces {
    /// 去动态看看, under a line to the squad.
    public let feed: () -> Void
    /// 回他, under a reply to the member's check-in or an answer to their reply.
    public let post: (CheckInID) -> Void
    /// 去衣橱看看, after a gift is opened: the wardrobe wearing it.
    public let wardrobe: (String) -> Void
    /// 招聘会, 简历 and 以前, top right.
    public let market: () -> Void
    public let resume: () -> Void
    public let earlier: () -> Void
    /// A gift piece's picture, as the wardrobe draws it.
    public let giftPicture: (String) -> AnyView
    /// A gift piece's name in the reader's language.
    public let giftName: (String) -> Text

    public init(
        feed: @escaping () -> Void, post: @escaping (CheckInID) -> Void, wardrobe: @escaping (String) -> Void,
        market: @escaping () -> Void, resume: @escaping () -> Void, earlier: @escaping () -> Void,
        giftPicture: @escaping (String) -> AnyView, giftName: @escaping (String) -> Text
    ) {
        (self.feed, self.post, self.wardrobe) = (feed, post, wardrobe)
        (self.market, self.resume, self.earlier) = (market, resume, earlier)
        (self.giftPicture, self.giftName) = (giftPicture, giftName)
    }
}

/// One of the coach's cards (the approved deck, 2026-11-08): its stage on top, then what kind it
/// is and when, what the coach said, and its buttons at the bottom. A gift opens in place
/// (拆开 → 一会儿再说 | 立刻穿上) and a challenge is answered in place (算了 | 接受挑战). `card` nil
/// is the last card, once everything is seen.
struct CoachDeckCard: View {
    let deck: CoachDeck
    let card: CoachPageCard?
    let coach: CoachSpeaker
    let coachLook: String
    let cast: DeckCast
    let places: CoachDeckPlaces
    /// The top card, whose buttons work; the ones under it only show.
    var isTop = true
    /// The gift's moment, kept here while it is opened as the member watches.
    @State private var moment: GiftMoment?
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CoachDeckStage(
                card: shown, coachLook: coachLook, cast: cast, gift: giftMoment,
                giftPicture: shown?.gift.map { places.giftPicture($0.piece) }
            )
            .frame(maxWidth: .infinity)
            .frame(height: DeckMetrics.stageHeight)
            VStack(alignment: .leading, spacing: Space.xs) {
                kindLine
                content
            }
            .padding(.horizontal, Space.m + Space.xxs)
            .padding(.top, Space.m)
            Spacer(minLength: Space.s)
            if isTop {
                buttons
                    .padding(.horizontal, Space.s + Space.xxs)
                    .padding(.bottom, Space.s + Space.xxs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(role: .bgCanvas, in: theme))
        .clipShape(RoundedRectangle(cornerRadius: DeckMetrics.corner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DeckMetrics.corner, style: .continuous)
                .strokeBorder(Color(role: .borderDefault, in: theme), lineWidth: Sizing.hairline)
        }
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: giftMoment)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(card.map { "coachDeck.card.\($0.kind.rawValue)" } ?? "coachDeck.allSeen")
    }

    /// The card as it stands now in the deck (a gift opened, a challenge answered).
    private var shown: CoachPageCard? { card.map(deck.current) }

    private var giftMoment: GiftMoment {
        if let moment { return moment }
        guard let gift = shown?.gift, gift.isOpen else { return .boxed }
        return gift.worn == true ? .worn : .stowed
    }

    // MARK: What it says

    /// What kind of card it is and when, such as 「今天对你说 · 8:00」; the coach's name on the last
    /// card.
    private var kindLine: some View {
        HStack(spacing: Space.xxs + 2) {
            if let icon = shown.flatMap(Self.icon) {
                Image(systemName: icon)
                    .font(.system(size: Sizing.smallIcon * 0.9, weight: .semibold))
                    .accessibilityHidden(true)
            }
            Group {
                if let shown {
                    Self.kind(shown.kind)
                    Text(verbatim: "· \(Self.time(of: shown.time))")
                } else {
                    Text(verbatim: coach.name)
                }
            }
            .typeStyle(TypeRamp.footnoteEmphasis)
            .lineLimit(1)
        }
        .foregroundStyle(Color(role: .fgMuted, in: theme))
    }

    @ViewBuilder private var content: some View {
        if let shown {
            switch shown.kind {
            case .challenge:
                if let challenge = shown.challenge { ChallengeFace(challenge: challenge) }
            case .gift:
                if let gift = shown.gift { giftFace(gift) }
            case .board, .note, .reply, .answer:
                big(Text(verbatim: shown.text ?? ""))
            }
        } else {
            big(Text("今天的都看过了。", bundle: .module))
        }
    }

    private func big(_ words: Text) -> some View {
        words
            .typeStyle(TypeRamp.title)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("coachDeck.text")
    }

    /// Boxed: 「送你一样东西，拆开看看。」. Opened: its picture, name and the coach's line, or 「已放进
    /// 衣橱」 once it is put away.
    @ViewBuilder private func giftFace(_ gift: CoachPageCard.Gift) -> some View {
        if giftMoment == .boxed {
            big(Text("送你一样东西，拆开看看。", bundle: .module))
        } else {
            HStack(spacing: Space.m) {
                places.giftPicture(gift.piece)
                    .padding(Space.xs)
                    .frame(width: DeckMetrics.giftTile, height: DeckMetrics.giftTile)
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.menu * 0.8, style: .continuous)
                            .strokeBorder(Color(role: .borderDefault, in: theme), lineWidth: Sizing.hairline)
                    }
                VStack(alignment: .leading, spacing: Space.xxs) {
                    places.giftName(gift.piece)
                        .typeStyle(TypeRamp.title)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .lineLimit(1)
                    Group {
                        if giftMoment == .stowed {
                            Text("已放进衣橱", bundle: .module)
                        } else if let line = gift.line {
                            Text(verbatim: line)
                        }
                    }
                    .typeStyle(TypeRamp.callout)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("coachDeck.gift")
        }
    }

    // MARK: Buttons

    @ViewBuilder private var buttons: some View {
        HStack(spacing: Space.s) {
            if let shown {
                switch shown.kind {
                case .board:
                    primary(Text("去动态看看", bundle: .module), id: "coachDeck.feed", action: places.feed)
                case .reply, .answer:
                    if let post = shown.checkIn {
                        primary(Text("回他", bundle: .module), id: "coachDeck.reply") { places.post(post) }
                    }
                case .challenge:
                    if shown.challenge?.answer == nil { challengeButtons(shown) }
                case .gift:
                    giftButtons(shown)
                case .note:
                    EmptyView()
                }
            } else {
                outline(Text("看以前的", bundle: .module), id: "coachDeck.earlier", grows: true, action: places.earlier)
            }
        }
        .disabled(shown.map { deck.sending.contains($0.key) } ?? false)
        .overlay(alignment: .top) {
            if let shown, deck.failed == shown.key {
                InlineFailure().offset(y: -Sizing.control)
            }
        }
    }

    private func challengeButtons(_ card: CoachPageCard) -> some View {
        Group {
            outline(Text("算了", bundle: .module), id: "coachDeck.decline", grows: false) {
                Task { await deck.answer(card, .declined) }
            }
            primary(Text("接受挑战", bundle: .module), id: "coachDeck.accept") {
                Task { await deck.answer(card, .accepted) }
            }
        }
    }

    @ViewBuilder private func giftButtons(_ card: CoachPageCard) -> some View {
        switch giftMoment {
        case .boxed:
            primary(Text("拆开", bundle: .module), id: "coachDeck.unwrap") { moment = .floating }
        case .floating:
            outline(Text("一会儿再说", bundle: .module), id: "coachDeck.later", grows: false) {
                Task { if await deck.open(card, worn: false) { moment = .stowed } }
            }
            primary(Text("立刻穿上", bundle: .module), id: "coachDeck.wear") {
                Task { if await deck.open(card, worn: true) { moment = .worn } }
            }
        case .worn, .stowed:
            if let piece = card.gift?.piece {
                primary(Text("去衣橱看看", bundle: .module), id: "coachDeck.wardrobe") { places.wardrobe(piece) }
            }
        }
    }

    private func primary(_ title: Text, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { title.frame(maxWidth: .infinity) }
            .buttonStyle(PrimaryButtonStyle(.regular))
            .accentTone(.scene)
            .accessibilityIdentifier(id)
    }

    /// The quieter choice beside the primary one: white with a hairline.
    private func outline(_ title: Text, id: String, grows: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title.frame(maxWidth: grows ? .infinity : nil)
        }
        .buttonStyle(SecondaryButtonStyle(.onInk))
        .overlay { Capsule().strokeBorder(Color(role: .borderDefault, in: theme), lineWidth: Sizing.hairline) }
        .accessibilityIdentifier(id)
    }

    // MARK: Words

    static func kind(_ kind: CoachPageCard.Kind) -> Text {
        switch kind {
        case .board: Text("对小队说", bundle: .module)
        case .note: Text("今天对你说", bundle: .module)
        case .challenge: Text("今日挑战", bundle: .module)
        case .gift: Text("送你的", bundle: .module)
        case .reply: Text("回复了你的训练", bundle: .module)
        case .answer: Text("回复了你", bundle: .module)
        }
    }

    static func icon(_ card: CoachPageCard) -> String? {
        switch card.kind {
        case .board: "megaphone.fill"
        case .note: nil
        case .challenge: "flag.fill"
        case .gift: "gift.fill"
        case .reply, .answer: "bubble.left.fill"
        }
    }

    /// The time on the reader's clock, with the day once it isn't today.
    static func time(of moment: Date) -> String {
        let locale = AppLanguage.current.locale
        var calendar = Calendar.current
        calendar.locale = locale
        let style: Date.FormatStyle =
            calendar.isDateInToday(moment)
            ? .dateTime.hour().minute() : .dateTime.month(.defaultDigits).day().hour().minute()
        return moment.formatted(style.locale(locale))
    }
}

/// A day's challenge: its amount big, in the scene's colour, with its unit, the title under it,
/// the coach's line, and the 挑战 stamp.
struct ChallengeFace: View {
    let challenge: CoachPageCard.Challenge
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            if let amount = challenge.amount {
                HStack(alignment: .firstTextBaseline, spacing: Space.xxs + 2) {
                    Text(verbatim: "\(amount)")
                        .typeStyle(TypeRamp.scoreEnding)
                        .minimumScaleFactor(0.6)
                    if let unit = challenge.unit {
                        Text(verbatim: unit).typeStyle(TypeRamp.title)
                    }
                }
                .foregroundStyle(Color(role: .fgAccent, in: theme))
                .lineLimit(1)
            }
            Text(verbatim: challenge.title)
                .typeStyle(TypeRamp.taskTitle)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .lineLimit(1)
            if let line = challenge.line {
                Text(verbatim: line)
                    .typeStyle(TypeRamp.callout)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            Text("挑战", bundle: .module)
                .typeStyle(TypeRamp.headline)
                .tracking(4)
                .foregroundStyle(Color(role: .fgAccent, in: theme))
                .padding(.horizontal, Space.s)
                .padding(.vertical, Space.xxs)
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.pick * 0.8, style: .continuous)
                        .strokeBorder(Color(role: .fgAccent, in: theme), lineWidth: 2.5)
                }
                .rotationEffect(.degrees(-12))
                .padding(.top, Space.s)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coachDeck.challenge")
    }
}

enum DeckMetrics {
    /// The stage's height on a card, as the approved deck has it on a 390-point phone.
    static let stageHeight: Double = 300
    static let corner: Double = 24
    /// An opened gift's picture tile.
    static let giftTile: Double = 84
    /// How far in, and down, each card under the top one peeks out.
    static let peek: Double = 12
}
#endif
