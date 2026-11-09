#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SquadDomain
import SwiftUI

/// 以前 (the approved design, 2026-11-09): every card not in the stack, newest first, under its
/// day, as plain list rows a page at a time as the member scrolls, with 全部 and 未读 at the top.
/// A row says what it is by its icon, what the coach said and, under it, which coach, when and how
/// it went; a boxed gift has its own 拆开. A row opens its card, which reads it.
public struct CoachEarlierPage: View {
    private let deck: CoachDeck
    private let places: CoachDeckPlaces
    private let open: (CoachPageCard) -> Void
    @Environment(\.sceneTheme) private var theme

    /// The icon's round tile.
    private static let iconTile: Double = 36
    /// How many rows from the end the next page is read.
    private static let readAhead = 5

    public init(deck: CoachDeck, places: CoachDeckPlaces, open: @escaping (CoachPageCard) -> Void) {
        (self.deck, self.places, self.open) = (deck, places, open)
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker(selection: filter) {
                Text("全部", bundle: .module).tag(CoachDeck.EarlierFilter.all)
                Text("未读", bundle: .module).tag(CoachDeck.EarlierFilter.unseen)
            } label: {
                Text("以前", bundle: .module)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Space.pageMargin)
            .padding(.vertical, Space.xs)
            .accessibilityIdentifier("coachEarlier.filter")
            if deck.earlier.isEmpty && !deck.isLoadingEarlier {
                StateView(
                    deck.earlierFilter == .unseen
                        ? Text("没有未读的", bundle: .module) : Text("还没有看过的", bundle: .module)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        .background(Color(role: .bgCanvas, in: theme))
        .navigationTitle(Text("以前", bundle: .module))
        .pushedPage()
    }

    private var filter: Binding<CoachDeck.EarlierFilter> {
        Binding(get: { deck.earlierFilter }, set: { picked in Task { await deck.showEarlier(picked) } })
    }

    private var list: some View {
        let cards = deck.earlier
        let loadFrom = max(0, cards.count - Self.readAhead)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Self.days(of: cards), id: \.day) { day in
                    SectionLabel(Self.title(of: day.day))
                        .padding(.top, Space.l)
                        .padding(.bottom, Space.xxs)
                    ForEach(day.cards, id: \.key) { card in
                        row(card)
                            .onAppear {
                                guard let index = cards.firstIndex(of: card), index >= loadFrom else { return }
                                Task { await deck.loadMoreEarlier() }
                            }
                    }
                }
                if deck.hasMoreEarlier {
                    LoadingDots()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.m)
                }
            }
            .padding(.horizontal, Space.pageMargin)
            .padding(.bottom, Space.l)
        }
    }

    // MARK: A row

    private func row(_ card: CoachPageCard) -> some View {
        HStack(spacing: Space.s) {
            Button {
                show(card)
            } label: {
                HStack(spacing: Space.s) {
                    icon(card)
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        summary(card)
                            .foregroundStyle(Color(role: .fgDefault, in: theme))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        detail(card)
                            .typeStyle(TypeRamp.footnote)
                            .foregroundStyle(Color(role: .fgMuted, in: theme))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !isBoxed(card) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: Sizing.smallIcon - 2, weight: .semibold))
                            .foregroundStyle(Color(role: .fgSubtle, in: theme))
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("coachEarlier.row.\(card.kind.rawValue)")
            if isBoxed(card) {
                Button {
                    show(card)
                } label: {
                    Text("拆开", bundle: .module)
                }
                .buttonStyle(PrimaryButtonStyle(.regular))
                .accentTone(.ink)
                .accessibilityIdentifier("coachEarlier.unwrap")
            }
        }
        .padding(.vertical, Space.s)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(role: .borderDefault, in: theme))
                .frame(height: Sizing.hairline)
        }
    }

    private func show(_ card: CoachPageCard) {
        deck.read(card)
        open(deck.current(card))
    }

    private func isBoxed(_ card: CoachPageCard) -> Bool {
        card.gift.map { !$0.isOpen } ?? false
    }

    /// What it is, in a round tile: ink once the challenge was done.
    private func icon(_ card: CoachPageCard) -> some View {
        let done = card.challenge?.completedBy != nil
        return Image(systemName: Self.symbol(card.kind))
            .font(.system(size: Sizing.smallIcon, weight: .semibold))
            .foregroundStyle(Color(role: done ? .fgOnBrand : .fgDefault, in: theme))
            .frame(width: Self.iconTile, height: Self.iconTile)
            .background(Circle().fill(Color(role: done ? .bgBrand : .bgSubtle, in: theme)))
            .accessibilityHidden(true)
    }

    private static func symbol(_ kind: CoachPageCard.Kind) -> String {
        switch kind {
        case .board: "megaphone"
        case .note: "text.bubble"
        case .challenge: "flag"
        case .gift: "gift"
        }
    }

    /// The coach's words; a challenge's amount in Barlow, its unit and title; a gift's name.
    private func summary(_ card: CoachPageCard) -> some View {
        Group {
            if let challenge = card.challenge {
                HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
                    if let amount = challenge.amount {
                        Text(verbatim: String(amount)).typeStyle(TypeRamp.scoreInline)
                    }
                    Text(verbatim: [challenge.unit, challenge.title].compactMap(\.self).joined(separator: " "))
                        .typeStyle(TypeRamp.calloutEmphasis)
                }
            } else if let gift = card.gift {
                (gift.isOpen ? places.giftName(gift.piece) : Text("送你一样东西", bundle: .module))
                    .typeStyle(TypeRamp.calloutEmphasis)
            } else {
                Text(verbatim: card.text ?? "").typeStyle(TypeRamp.callout)
            }
        }
    }

    /// 「毛头 · 08:00 · 已完成」: who said it (a coach that left by its own name), to whom, when,
    /// and how it went.
    private func detail(_ card: CoachPageCard) -> Text {
        let words = Bundle.module.inAppLanguage
        let word = { (key: String) in words.localizedString(forKey: key, value: nil, table: nil) }
        let time = card.time.formatted(.dateTime.hour().minute().locale(AppLanguage.current.locale))
        let parts = [card.coach.name, card.kind == .board ? word("对小队") : nil, time, Self.outcome(card).map(word)]
        return Text(verbatim: parts.compactMap(\.self).joined(separator: " · "))
    }

    /// How it went, as a String Catalog key: 已完成, 已接受, 没接, 已穿上 or 在衣橱.
    private static func outcome(_ card: CoachPageCard) -> String? {
        if let challenge = card.challenge {
            if challenge.completedBy != nil { return "已完成" }
            switch challenge.answer {
            case .accepted: return "已接受"
            case .declined: return "没接"
            case nil: return nil
            }
        }
        if let gift = card.gift, gift.isOpen { return gift.worn == true ? "已穿上" : "在衣橱" }
        return nil
    }

    // MARK: Days

    /// The cards under their day on the reader's clock, in the order they come.
    private struct Day {
        let day: Date
        var cards: [CoachPageCard]
    }

    private static func days(of cards: [CoachPageCard]) -> [Day] {
        let calendar = Calendar.current
        var days: [Day] = []
        for card in cards {
            let day = calendar.startOfDay(for: card.time)
            if days.last?.day == day {
                days[days.count - 1].cards.append(card)
            } else {
                days.append(Day(day: day, cards: [card]))
            }
        }
        return days
    }

    /// 今天, 昨天 or 11月7日.
    private static func title(of day: Date) -> Text {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return Text("今天", bundle: .module) }
        if calendar.isDateInYesterday(day) { return Text("昨天", bundle: .module) }
        let locale = AppLanguage.current.locale
        return Text(verbatim: day.formatted(.dateTime.month(.defaultDigits).day().locale(locale)))
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
