#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SquadDomain
import SwiftUI

/// 以前: the coach's cards the member has seen, newest first, as plain rows with no count. A row
/// opens its card, where a gift still in its box opens (拆开).
public struct CoachEarlierPage: View {
    private let deck: CoachDeck
    private let places: CoachDeckPlaces
    private let open: (CoachPageCard) -> Void
    @Environment(\.sceneTheme) private var theme

    public init(deck: CoachDeck, places: CoachDeckPlaces, open: @escaping (CoachPageCard) -> Void) {
        (self.deck, self.places, self.open) = (deck, places, open)
    }

    public var body: some View {
        Group {
            if deck.earlier.isEmpty {
                StateView(Text("还没有看过的", bundle: .module))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(deck.earlier, id: \.key) { card in
                            Button {
                                open(card)
                            } label: {
                                row(card)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("coachEarlier.row.\(card.kind.rawValue)")
                            Rectangle()
                                .fill(Color(role: .borderDefault, in: theme))
                                .frame(height: Sizing.hairline)
                        }
                    }
                    .padding(.horizontal, Space.pageMargin)
                }
            }
        }
        .background(Color(role: .bgCanvas, in: theme))
        .navigationTitle(Text("以前", bundle: .module))
        .pushedPage()
    }

    private func row(_ card: CoachPageCard) -> some View {
        HStack(spacing: Space.s) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                summary(card)
                    .typeStyle(TypeRamp.body)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .lineLimit(2)
                HStack(spacing: Space.xxs) {
                    CoachDeckCard.kind(card.kind)
                    Text(verbatim: "· \(CoachDeckCard.time(of: card.time))")
                }
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let gift = card.gift, !gift.isOpen {
                Image(systemName: "gift.fill")
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .accessibilityHidden(true)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: Sizing.smallIcon, weight: .semibold))
                .foregroundStyle(Color(role: .fgSubtle, in: theme))
                .accessibilityHidden(true)
        }
        .padding(.vertical, Space.s)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// What the row says: the coach's words, the challenge, or the gift (its name once opened).
    private func summary(_ card: CoachPageCard) -> Text {
        if let challenge = card.challenge {
            return Text(
                verbatim: [challenge.amount.map(String.init), challenge.unit, challenge.title].compactMap(\.self)
                    .joined(separator: " "))
        }
        if let gift = card.gift {
            return gift.isOpen ? places.giftName(gift.piece) : Text("送你一样东西，拆开看看。", bundle: .module)
        }
        return Text(verbatim: card.text ?? "")
    }
}

/// One card from 以前 on its own, as it was in the stack: a boxed gift opens here.
public struct CoachCardPage: View {
    private let deck: CoachDeck
    private let card: CoachPageCard
    private let cast: DeckCast
    private let places: CoachDeckPlaces
    @Environment(\.sceneTheme) private var theme

    public init(deck: CoachDeck, card: CoachPageCard, cast: DeckCast, places: CoachDeckPlaces) {
        (self.deck, self.card, self.cast, self.places) = (deck, card, cast, places)
    }

    public var body: some View {
        CoachDeckCard(deck: deck, card: card, coach: card.coach, coachLook: card.look, cast: cast, places: places)
            .padding(.horizontal, Space.pageMargin)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(role: .bgCanvas, in: theme))
            .navigationTitle(Text(verbatim: card.coach.name))
            .pushedPage()
    }
}
#endif
