#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SquadDomain
import SwiftUI

// A coach message (教练消息卡, Tracy 2026-11-12) on the coach's page: one template filled by data.
// Its line, then each slot only when filled (a body, what it is about, 软糖星 to tap, a box to
// type in), and its buttons at the bottom, whose steps are data too. A tap that turns the card
// shows the next card in place; one that closes it shows its thanks.

/// A message's words in the app's language.
enum CoachMessageWords {
    static func text(_ words: CatalogNames) -> String {
        words.localized(in: [AppLanguage.current.rawValue])
    }
}

/// What a message's card says, between its stage and its buttons.
struct MessageFace: View {
    let deck: CoachDeck
    let card: CoachPageCard
    let message: CoachMessage
    /// The top card, whose stars can be tapped; the ones under it only show.
    let isTop: Bool
    @Binding var typed: String
    var typing: FocusState<Bool>.Binding
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        switch message.place {
        case .closed(let path):
            if let shown = message.card(at: path) {
                big(shown.thanks ?? shown.line)
            }
        case .card(let path):
            if let shown = message.card(at: path) {
                face(shown)
            }
        }
    }

    private func face(_ shown: CoachMessage.Card) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            VStack(alignment: .leading, spacing: Space.xs) {
                big(shown.line)
                if let body = shown.body {
                    Text(verbatim: CoachMessageWords.text(body))
                        .typeStyle(TypeRamp.callout)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let about = shown.about { aboutRow(about) }
            if shown.stars { stars(on: shown) }
            if let input = shown.input { box(input) }
        }
    }

    private func big(_ words: CatalogNames) -> some View {
        Text(verbatim: CoachMessageWords.text(words))
            .typeStyle(TypeRamp.title)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("coachDeck.text")
    }

    /// What it is about: its symbol in a round tile, its name and a line under it.
    private func aboutRow(_ about: CoachMessage.About) -> some View {
        HStack(spacing: Space.s) {
            if let icon = about.icon {
                Image(systemName: icon)
                    .font(.system(size: Sizing.smallIcon, weight: .semibold))
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .frame(width: MessageMetrics.aboutTile, height: MessageMetrics.aboutTile)
                    .background(Circle().fill(Color(role: .bgSubtle, in: theme)))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(verbatim: CoachMessageWords.text(about.name))
                    .typeStyle(TypeRamp.calloutEmphasis)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .lineLimit(1)
                if let detail = about.detail {
                    Text(verbatim: CoachMessageWords.text(detail))
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .lineLimit(2)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coachDeck.about")
    }

    /// Five 软糖星: tapped once, the stars given stand.
    private func stars(on shown: CoachMessage.Card) -> some View {
        let given = message.answered[shown.path]?.stars
        var pick: ((Int) -> Void)?
        if isTop, given == nil, !deck.sending.contains(card.key) {
            pick = { picked in Task { await deck.give(picked, on: card, at: shown.path) } }
        }
        return StarRating(rating: given ?? 0, size: MessageMetrics.star, onPick: pick)
            .accessibilityIdentifier("coachDeck.stars")
    }

    /// The box to type in, a few lines at most, as long as the API keeps.
    private func box(_ input: CoachMessage.Input) -> some View {
        let prompt = Text(verbatim: input.placeholder.map(CoachMessageWords.text) ?? "")
        return TextField(
            text: $typed, prompt: prompt.foregroundStyle(Color(role: .fgSubtle, in: theme)), axis: .vertical
        ) {
            prompt
        }
        .typeStyle(TypeRamp.field)
        .foregroundStyle(Color(role: .fgDefault, in: theme))
        .lineLimit(1...MessageMetrics.boxLines)
        .focused(typing)
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .frame(minHeight: Sizing.control)
        .overlay {
            RoundedRectangle(cornerRadius: Radius.menu, style: .continuous)
                .strokeBorder(Color(role: .borderDefault, in: theme), lineWidth: Sizing.hairline)
        }
        .disabled(!isTop)
        .onChange(of: typed) { _, now in
            if now.utf16.count > CoachMessage.textLimit { typed = CoachMessage.cut(now) }
        }
        .accessibilityIdentifier("coachDeck.box")
    }
}

/// A message card's buttons, left to right, each running its steps on a tap; none once a tap
/// closed the card. A button that sends the box's words as 意见反馈 waits for something typed.
struct MessageButtons: View {
    let deck: CoachDeck
    let card: CoachPageCard
    let message: CoachMessage
    @Binding var typed: String
    var typing: FocusState<Bool>.Binding
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        if case .card(let path) = message.place, let shown = message.card(at: path), !shown.buttons.isEmpty {
            HStack(spacing: Space.s) {
                ForEach(shown.buttons) { button in
                    styled(button, at: path)
                        .disabled(button.sendsFeedback && CoachMessage.text(typed) == nil)
                }
            }
        }
    }

    @ViewBuilder private func styled(_ button: CoachMessage.Button, at path: String) -> some View {
        let tap = { run(button, at: path) }
        switch button.style {
        case .primary:
            Button(action: tap) { label(button).frame(maxWidth: .infinity) }
                .buttonStyle(PrimaryButtonStyle(.regular))
                .accentTone(.scene)
                .accessibilityIdentifier("coachDeck.button.\(button.id)")
        case .outline:
            Button(action: tap) { label(button).frame(maxWidth: .infinity) }
                .buttonStyle(SecondaryButtonStyle(.onInk))
                .overlay {
                    Capsule().strokeBorder(Color(role: .borderDefault, in: theme), lineWidth: Sizing.hairline)
                }
                .accessibilityIdentifier("coachDeck.button.\(button.id)")
        case .plain:
            Button(action: tap) {
                label(button)
                    .typeStyle(TypeRamp.calloutEmphasis)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .frame(maxWidth: .infinity, minHeight: Sizing.control)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("coachDeck.button.\(button.id)")
        }
    }

    private func label(_ button: CoachMessage.Button) -> some View {
        HStack(spacing: Space.xxs + 2) {
            if let icon = button.icon {
                Image(systemName: icon).accessibilityHidden(true)
            }
            Text(verbatim: CoachMessageWords.text(button.label))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func run(_ button: CoachMessage.Button, at path: String) {
        typing.wrappedValue = false
        Task {
            await deck.tap(button, on: card, at: path, typed: typed)
            // On to another card, or folded to its thanks: the box starts empty again.
            if deck.current(card).message?.place != .card(path) { typed = "" }
        }
    }
}

enum MessageMetrics {
    /// A 软糖星's size on a card.
    static let star: Double = 36
    /// The round tile of what a card is about.
    static let aboutTile: Double = 40
    /// The most lines the box grows to before it scrolls.
    static let boxLines = 4
}
#endif
