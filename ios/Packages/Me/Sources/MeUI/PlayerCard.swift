#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import MeDomain
import SwiftUI

/// A player card, like a baseball card, as the approved 头衔徽章 design draws it: the front has the
/// number over the title worn and its badge, the character, the name, squad and year, and the
/// headline numbers; a tap turns it over to the career line and the badge board (徽章板), where a
/// badge opens its own card. Ink card stock with white type, the character in a light grey window,
/// standing on faint court lines. The member's own on 我 can wear a title from a badge's card
/// (`equip`); a squadmate's can't.
struct PlayerCard: View {
    let face: PlayerCardFace
    /// Wears a title or team badge; nil on a squadmate's card, which shows no 装备.
    var equip: ((Wearable) -> Void)?
    /// What this phone saw of the member's own board, for NEW and the turns to it a notice asks
    /// for; nil on a squadmate's card.
    var marks: BadgeMarks?
    /// The colour of the 轻点翻面 line under the card: muted on a page, on-ink over a dim; nil
    /// leaves the line out (我, where tiles follow the card).
    var hint: ColorRole? = .fgMuted
    /// Spans the width it is given at the card's proportions (我), instead of its own 300 points.
    var fillsWidth = false
    @State private var opened: OpenedBadge?
    /// What a squadmate's card's back shows: their 出赛表, or in its place their badge board or
    /// what they wear.
    @State private var backSide = BackSide.schedule
    static var size: CGSize { TradingCard.size }

    var body: some View {
        FlippingCard(hint: hint, fillsWidth: fillsWidth, identifier: "me.card", backRequested: boardRequested) {
            CardFront(face: face)
        } back: {
            // Turned over again, a squadmate's back opens on their 出赛表. The stack keeps one
            // identity while the back switches sides inside it, so only the turn resets it.
            ZStack { back }.onDisappear { backSide = .schedule }
        }
        .sheet(item: $opened) { badge in
            BadgeCard(
                badge: badge.card, isWorn: face.board.wears(badge.wearable),
                equip: equip.map { equip in
                    {
                        equip(badge.wearable)
                        opened = nil
                    }
                })
        }
    }

    /// A notice's turn to the board, on the member's own card.
    private var boardRequested: Binding<Bool> {
        Binding(get: { marks?.boardRequested ?? false }, set: { marks?.boardRequested = $0 })
    }

    /// Opens a badge's card, and it is no longer NEW.
    private func open(_ badge: OpenedBadge) {
        marks?.see(badge.mark, on: face.board)
        opened = badge
    }

    /// A squadmate's card turns over to their 出赛表 this week, whose badges turn the same side to
    /// their badge board and 出赛表 back again (Tracy, 2026-11-08, A), and whose 穿搭 to what they
    /// wear (2026-11-10, A); the member's own (and one from an older server) to the board itself.
    @ViewBuilder private var back: some View {
        if let schedule = face.schedule {
            switch backSide {
            case .schedule:
                ScheduleBack(
                    face: face, schedule: schedule, openBoard: { backSide = .board },
                    openOutfit: { backSide = .outfit })
            case .board:
                CardBack(face: face, toSchedule: { backSide = .schedule }, open: open)
            case .outfit:
                OutfitBack(face: face) { backSide = .schedule }
            }
        } else {
            CardBack(face: face, news: marks?.news(on: face.board) ?? [], open: open)
        }
    }

    private enum BackSide {
        case schedule, board, outfit
    }
}

/// The front: in the character's window, the number over a short bar in the badge's colour and
/// the title worn, with its badge at the top right; then the name, squad and the year they
/// joined, and 练了, 本周 and 徽章.
private struct CardFront: View {
    let face: PlayerCardFace
    @Environment(\.sceneTheme) private var theme

    /// What the front wears: a title, or a team badge in the app's language.
    private var worn: WornTitle? { face.board.wornTitle(in: [AppLanguage.current.rawValue]) }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { window in
                MeStage(character: face.character, size: Self.figure(in: window.size.width), floor: .borderDefault)
                    .padding(.bottom, Space.s)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .overlay(alignment: .topLeading) { numberAndTitle }
            .overlay(alignment: .topTrailing) {
                if let worn {
                    TitleBadgeView(
                        shape: worn.badge.shape, colour: worn.badge.colour, tone: worn.badge.tone,
                        glyph: worn.badge.glyph,
                        size: Self.badgeSize
                    )
                    .padding(Space.s)
                    .accessibilityIdentifier("me.wornBadge")
                }
            }
            .background {
                Color(role: .bgSubtle, in: theme)
                    .overlay {
                        CourtLines()
                            .stroke(Color(role: .borderBrandFloor, in: theme), lineWidth: Self.courtLine)
                            .accessibilityHidden(true)
                    }
            }
            .clipShape(TradingCard.window)
            HStack(alignment: .center, spacing: Space.xs) {
                nameAndSquad
                streakTickets
            }
            .padding(.horizontal, Space.xxs)
            .padding(.top, Space.s)
            stats
        }
    }

    /// 60 points, as the approved front has it.
    private static let badgeSize: Double = 60
    /// The court's lines, 2 points as the approved front has them.
    private static let courtLine: Double = 2

    /// The character, 46% of the window's width at its own 4:5, as the approved front has it.
    private static func figure(in width: Double) -> CGSize {
        CGSize(width: width * 0.46, height: width * 0.46 * 1.25)
    }
    /// The bar under the number: short and thin, in the worn badge's colour.
    private static let bar = CGSize(width: 28, height: 3)

    /// The number, the bar and the title down the window's left, clear of the badge.
    private var numberAndTitle: some View {
        VStack(alignment: .leading, spacing: Space.xxs + Space.xxs / 2) {
            if let number = face.number {
                Text(verbatim: number.text)
                    .typeStyle(TypeRamp.scoreHero)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .monospacedDigit()
                    .fixedSize()
                    .accessibilityLabel(Text(copy: "card.number \(number.text)", bundle: .module))
                    .accessibilityIdentifier("me.cardNumber")
            }
            if let worn {
                Capsule()
                    .fill(TitleBadgeView.faceColor(colour: worn.badge.colour, tone: worn.badge.tone))
                    .frame(width: Self.bar.width, height: Self.bar.height)
                    .accessibilityHidden(true)
                Text(verbatim: worn.title)
                    .typeStyle(TypeRamp.cardTitle)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityIdentifier("me.wornTitle")
            }
        }
        .padding(.leading, Space.m)
        .padding(.top, Space.xs)
        // Clear of the badge at the top right.
        .padding(.trailing, Self.badgeSize + Space.s * 2)
    }

    private var nameAndSquad: some View {
        VStack(alignment: .leading, spacing: Space.xxs / 2) {
            Text(face.character.nickname)
                .typeStyle(TypeRamp.title)
                .foregroundStyle(Color(role: .fgOnInk, in: theme))
                .lineLimit(1)
                .accessibilityIdentifier("me.nickname")
            // The squad, then the year they joined, under the name: the 外卡 stand at the right.
            HStack(alignment: .lastTextBaseline, spacing: Space.xs) {
                if let squad = face.squadName {
                    Text(squad)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
                        .lineLimit(1)
                        .accessibilityIdentifier("me.squadName")
                }
                if let year = face.joinedAt.map({ String(Calendar.current.component(.year, from: $0)) }) {
                    Text(copy: "card.since \(year)", bundle: .module)
                        .typeStyle(TypeRamp.label)
                        .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
                        .fixedSize()
                        .accessibilityIdentifier("me.since")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The 外卡 for each streak still going (Tracy, 2026-11-10, A): days trained in a row, then
    /// days with a meal, beside the name; a broken one isn't shown.
    @ViewBuilder private var streakTickets: some View {
        if face.streaks != .none {
            HStack(spacing: Space.xxs) {
                if face.streaks.training > 0 {
                    StreakTicket(days: face.streaks.training, streak: .training, ink: .fgOnInk, on: .bgInk)
                        .accessibilityIdentifier("me.streak.training")
                }
                if face.streaks.meals > 0 {
                    StreakTicket(days: face.streaks.meals, streak: .meals, ink: .fgOnInk, on: .bgInk)
                        .accessibilityIdentifier("me.streak.meals")
                }
            }
        }
    }

    private var stats: some View {
        HStack(alignment: .top, spacing: Space.xs) {
            FrontStat(label: Text(copy: "训练", bundle: .module)) {
                Score(count: face.counts.trainedDays, size: .card, onInk: true)
                    .accessibilityIdentifier("me.trainedDays")
            }
            if let week = face.week {
                FrontStat(label: Text(copy: "本周", bundle: .module)) {
                    Score(count: week.trainedDays, goal: week.plannedDays, size: .card, onInk: true)
                }
            }
            FrontStat(label: Text(copy: "徽章", bundle: .module)) {
                Score(count: face.board.count, size: .card, onInk: true)
                    .accessibilityIdentifier("me.titles")
            }
        }
        .padding(.horizontal, Space.xxs)
        .padding(.top, Space.s)
        .padding(.bottom, Space.xxs)
        .overlay(alignment: .top) { Hairline(on: .ink).padding(.horizontal, Space.xxs) }
        .padding(.top, Space.s)
    }
}

/// A headline number on the front, over its word. Each takes an equal share of the row, so a new
/// stat is one more of these.
private struct FrontStat<Value: View>: View {
    let label: Text
    @ViewBuilder let value: Value
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs / 2) {
            value
            label
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The back: the name and number, the career count of 练了 large with 健康餐 and 请假条 beside
/// it, then the badge board, three to a row, ending on the dashed slot of the next Sunday's. On a
/// squadmate's card it is opened from their 出赛表, with 「‹ 徽章」 back to it and no next slot.
private struct CardBack: View {
    let face: PlayerCardFace
    /// Back to a squadmate's 出赛表; nil on the member's own card.
    var toSchedule: (() -> Void)?
    /// The badges that wear NEW, by `BadgeNews`' marks; empty on a squadmate's card.
    var news: Set<String> = []
    let open: (OpenedBadge) -> Void
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // A squadmate's goes back to their 出赛表 as 穿搭 does, with how many badges.
            CardSideHeader(
                face: face,
                back: toSchedule.map {
                    CardSideHeader.Back(
                        title: Text(copy: "徽章", bundle: .module), count: Text(verbatim: "\(face.board.count)"),
                        identifier: "me.cardBackToSchedule", action: $0)
                })
            HStack(alignment: .lastTextBaseline, spacing: Space.xs) {
                Score(count: face.counts.trainedDays, size: .hero, onInk: true)
                Text(copy: "card.career \(face.counts.healthyMeals) \(face.counts.disclaimers)", bundle: .module)
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
                    // One line, shrunk to fit, so a word never breaks across lines.
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.top, Space.xs)
            .accessibilityElement(children: .combine)
            // The member's own names the board here; a squadmate's names it in the header.
            if toSchedule == nil {
                HStack(alignment: .firstTextBaseline) {
                    Text(copy: "徽章", bundle: .module)
                        .typeStyle(TypeRamp.label)
                        .foregroundStyle(Color(role: .fgOnInk, in: theme))
                    Spacer()
                    Text(verbatim: "\(face.board.count)")
                        .typeStyle(TypeRamp.scoreCaption)
                        .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
                        .monospacedDigit()
                }
                .padding(.top, Space.s)
                .overlay(alignment: .top) { Hairline(on: .ink).offset(y: -Space.xxs) }
                .padding(.top, Space.xxs)
            }
            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: Space.s) {
                    // The team's tickets first: few, and given by hand.
                    ForEach(face.board.teamBadges) { badge in
                        Button {
                            open(.team(badge))
                        } label: {
                            TeamBadgeCell(
                                badge: badge, isWorn: face.board.wears(.teamBadge(badge.id)),
                                isNew: news.contains(BadgeNews.key(badge)))
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityIdentifier("me.teamBadge")
                    }
                    ForEach(face.board.titles) { title in
                        Button {
                            open(.title(title))
                        } label: {
                            BadgeCell(
                                title: title, isWorn: face.board.wears(.title(title.title)),
                                isNew: news.contains(BadgeNews.key(title)))
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityIdentifier("me.badge")
                    }
                    if toSchedule == nil { NextBadgeCell() }
                }
                .padding(.vertical, Space.s)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.horizontal, Space.xs)
        .padding(.top, Space.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 3)
}

/// The card window's faint court, as the approved front draws it on a 354 × 324 window: a
/// boundary inset from the window's edge, a half line at 196 behind the character and a centre
/// circle of 70 on it, whole inside the court. The card's only backdrop for now; more can come
/// later as backdrops a member unlocks.
private struct CourtLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let court = rect.insetBy(dx: Space.s, dy: Space.s)
        path.addRoundedRect(in: court, cornerSize: CGSize(width: Space.xxs, height: Space.xxs))
        let halfLine = rect.minY + rect.height * 196 / 324
        path.move(to: CGPoint(x: court.minX, y: halfLine))
        path.addLine(to: CGPoint(x: court.maxX, y: halfLine))
        let radius = rect.width * 70 / 354
        path.addEllipse(
            in: CGRect(x: rect.midX - radius, y: halfLine - radius, width: radius * 2, height: radius * 2)
        )
        return path
    }
}
#endif
