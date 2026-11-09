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
        feed: @escaping () -> Void, wardrobe: @escaping (String) -> Void,
        market: @escaping () -> Void, resume: @escaping () -> Void, earlier: @escaping () -> Void,
        giftPicture: @escaping (String) -> AnyView, giftName: @escaping (String) -> Text
    ) {
        (self.feed, self.wardrobe) = (feed, wardrobe)
        (self.market, self.resume, self.earlier) = (market, resume, earlier)
        (self.giftPicture, self.giftName) = (giftPicture, giftName)
    }
}

/// One of the coach's cards (the approved deck, 2026-11-08): its stage on top, then what kind it
/// is and when, what the coach said, and its buttons at the bottom. A gift opens in place
/// (拆开 → 一会儿再说 | 立刻穿上) and a challenge is answered in place (接受挑战, or 不接挑战 with an
/// optional word to the coach on why). `card` nil is the last card, once everything is seen.
struct CoachDeckCard: View {
    let deck: CoachDeck
    let card: CoachPageCard?
    let coach: CoachSpeaker
    let coachLook: String
    let cast: DeckCast
    let places: CoachDeckPlaces
    /// The top card, whose buttons work; the ones under it only show.
    var isTop = true
    /// Swipes the card into 以前, once its challenge is answered; nil on a card opened from 以前.
    var putAway: ((CoachPageCard) -> Void)?
    /// The gift's moment, kept here while it is opened as the member watches.
    @State private var moment: GiftMoment?
    /// 接受挑战 was tapped and went through: the stamp comes down and the button pops.
    @State private var stamped = false
    /// What the member is telling the coach about 不接挑战.
    @State private var reason = ""
    /// The reason's field has the keyboard: the stage gives up its height so the field and its
    /// button stay above the keyboard.
    @FocusState private var typing: Bool
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CoachDeckStage(
                card: shown, coachLook: coachLook, cast: cast, gift: giftMoment,
                giftPicture: shown?.gift.map { places.giftPicture($0.piece) }
            )
            .frame(maxWidth: .infinity)
            .frame(
                minHeight: typing ? 0 : DeckMetrics.stageHeight, maxHeight: DeckMetrics.stageHeight,
                alignment: .bottom
            )
            .clipped()
            .layoutPriority(typing ? -1 : 0)
            VStack(alignment: .leading, spacing: Space.xs) {
                kindLine
                content
            }
            .padding(.horizontal, Space.m + Space.xxs)
            .padding(.top, Space.m)
            if !typing { Spacer(minLength: Space.s) }
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
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: typing)
        .accessibilityElement(children: .contain)
        // The card's name for the UI tests goes on a marker of the card's own bounds: a container's
        // frame takes in its stage's scene art, which stands taller than the stage and is cut to it.
        .background {
            Color.clear
                .accessibilityElement()
                .accessibilityIdentifier(card.map { "coachDeck.card.\($0.kind.rawValue)" } ?? "coachDeck.allSeen")
        }
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
                if let challenge = shown.challenge { ChallengeFace(challenge: challenge, stamped: stamped) }
            case .gift:
                if let gift = shown.gift { giftFace(gift) }
            case .board, .note:
                big(Text(verbatim: shown.text ?? ""))
            }
        } else {
            big(Text(copy: "暂时没有新消息", bundle: .module))
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
            big(Text(copy: "送你一样东西，拆开看看。", bundle: .module))
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
                            Text(copy: "已放进衣橱", bundle: .module)
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
        Group {
            if let shown, shown.kind == .challenge {
                // Held while its stamp plays, then the card goes.
                if shown.challenge?.answer == nil || stamped {
                    ChallengeAnswers(
                        deck: deck, card: shown, coachName: coach.name, stamped: $stamped, reason: $reason,
                        typing: $typing, putAway: putAway)
                }
            } else {
                HStack(spacing: Space.s) { rowButtons }
            }
        }
        .disabled(shown.map { deck.sending.contains($0.key) } ?? false)
        .overlay(alignment: .top) {
            if let shown, deck.failed == shown.key {
                InlineFailure().offset(y: -Sizing.control)
            }
        }
    }

    /// Every card's buttons but a challenge's, side by side.
    @ViewBuilder private var rowButtons: some View {
        if let shown {
            switch shown.kind {
            case .board:
                primary(Text(copy: "去动态看看", bundle: .module), id: "coachDeck.feed", action: places.feed)
            case .gift:
                giftButtons(shown)
            case .note, .challenge:
                EmptyView()
            }
        } else {
            outline(Text(copy: "看以前的", bundle: .module), id: "coachDeck.earlier", grows: true, action: places.earlier)
        }
    }

    @ViewBuilder private func giftButtons(_ card: CoachPageCard) -> some View {
        switch giftMoment {
        case .boxed:
            primary(Text(copy: "拆开", bundle: .module), id: "coachDeck.unwrap") { moment = .floating }
        case .floating:
            outline(Text(copy: "一会儿再说", bundle: .module), id: "coachDeck.later", grows: false) {
                Task { if await deck.open(card, worn: false) { moment = .stowed } }
            }
            primary(Text(copy: "立刻穿上", bundle: .module), id: "coachDeck.wear") {
                Task { if await deck.open(card, worn: true) { moment = .worn } }
            }
        case .worn, .stowed:
            if let piece = card.gift?.piece {
                primary(Text(copy: "去衣橱看看", bundle: .module), id: "coachDeck.wardrobe") { places.wardrobe(piece) }
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
        case .board: Text(copy: "对小队说", bundle: .module)
        case .note: Text(copy: "今天对你说", bundle: .module)
        case .challenge: Text(copy: "今日挑战", bundle: .module)
        case .gift: Text(copy: "送你的", bundle: .module)
        }
    }

    static func icon(_ card: CoachPageCard) -> String? {
        switch card.kind {
        case .board: "megaphone.fill"
        case .note: nil
        case .challenge: "flag.fill"
        case .gift: "gift.fill"
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

enum DeckMetrics {
    /// The stage's height on a card, as the approved deck has it on a 390-point phone.
    static let stageHeight: Double = 300
    static let corner: Double = 24
    /// An opened gift's picture tile.
    static let giftTile: Double = 84
    /// How far in, and down, each card under the top one peeks out.
    static let peek: Double = 12
    /// The 挑战 stamp's width.
    static let stamp: Double = 80
    /// Seconds each beat of the stamp's slam and the button's squash takes.
    static let squash: Double = 0.08
    /// Seconds 接受挑战's stamp shows before the card goes into 以前.
    static let stampHold: Double = 0.6
}
#endif
