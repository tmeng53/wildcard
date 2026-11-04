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
    /// Wears a title (nil: the latest again); nil on a squadmate's card, which shows no 装备.
    var equip: ((String) -> Void)?
    /// The colour of the 轻点翻面 line under the card: muted on a page, on-ink over a dim.
    var hint: ColorRole = .fgMuted
    @State private var showsBack = false
    /// How far the card has turned on its vertical axis, in degrees: it turns edge-on, swaps sides
    /// out of sight and turns back.
    @State private var turn: Double = 0
    @State private var isTurning = false
    @State private var opened: BoardTitle?
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let size = CGSize(width: 300, height: 460)

    var body: some View {
        VStack(spacing: Space.s) {
            Group {
                if showsBack {
                    // The back's badges are buttons of their own, so the back is no button: a
                    // tap anywhere else on it turns it over.
                    sided(CardBack(face: face) { opened = $0 })
                        .onTapGesture(perform: flip)
                        .accessibilityElement(children: .contain)
                        .accessibilityAction(named: Text("轻点翻面", bundle: .module), flip)
                        .accessibilityIdentifier("me.cardBack")
                } else {
                    Button(action: flip) { sided(CardFront(face: face)) }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityHint(Text("轻点翻面", bundle: .module))
                        .accessibilityIdentifier("me.card")
                }
            }
            .rotation3DEffect(.degrees(turn), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            // It turns over rather than swipes, so it says so.
            Text("轻点翻面", bundle: .module)
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: hint, in: theme))
                .accessibilityHidden(true)
        }
        .sheet(item: $opened) { title in
            BadgeCard(
                title: title, isWorn: face.board.worn == title.title,
                equip: equip.map { equip in
                    {
                        equip(title.title)
                        opened = nil
                    }
                })
        }
    }

    private static let shape = RoundedRectangle(cornerRadius: Radius.card + Space.xxs, style: .continuous)

    /// A side on the card's stock, at the card's size.
    private func sided(_ side: some View) -> some View {
        side
            .padding(Space.xs)
            .frame(width: Self.size.width, height: Self.size.height)
            .background(Color(role: .bgInk, in: theme), in: Self.shape)
            .contentShape(Self.shape)
    }

    /// Half a turn each way on the page spring's time; with Reduce Motion on, the sides swap with
    /// a fade.
    private func flip() {
        guard !isTurning else { return }
        if reduceMotion {
            withAnimation(.wildcard(Motion.page, reduceMotion: true)) { showsBack.toggle() }
            return
        }
        isTurning = true
        let half = Motion.page.response / 2
        withAnimation(.easeIn(duration: half)) {
            turn = 90
        } completion: {
            showsBack.toggle()
            turn = -90
            withAnimation(.easeOut(duration: half)) {
                turn = 0
            } completion: {
                isTurning = false
            }
        }
    }
}

/// The front: in the character's window, the number over a short bar in the badge's colour and
/// the title worn, with its badge at the top right; then the name, squad and the year they
/// joined, and 练了, 本周 and 徽章.
private struct CardFront: View {
    let face: PlayerCardFace
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            MeStage(character: face.character, floor: .borderDefault)
                .padding(.bottom, -Space.xxs)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .overlay(alignment: .topLeading) { numberAndTitle }
                .overlay(alignment: .topTrailing) {
                    if let worn = face.board.wornTitle {
                        TitleBadgeView(
                            shape: worn.badge.shape, colour: worn.badge.colour, glyph: worn.badge.glyph,
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
                                .stroke(Color(role: .borderBrandFloor, in: theme), lineWidth: Sizing.selectionStroke)
                                .accessibilityHidden(true)
                        }
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.pick, style: .continuous))
            HStack(alignment: .lastTextBaseline, spacing: Space.xs) {
                nameAndSquad
                if let year = face.joinedAt.map({ String(Calendar.current.component(.year, from: $0)) }) {
                    Text("card.since \(year)", bundle: .module)
                        .typeStyle(TypeRamp.label)
                        .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
                        .accessibilityIdentifier("me.since")
                }
            }
            .padding(.horizontal, Space.xxs)
            .padding(.top, Space.s)
            stats
        }
    }

    /// 60 points, as the approved front has it.
    private static let badgeSize: Double = 60
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
                    .accessibilityLabel(Text("card.number \(number.text)", bundle: .module))
                    .accessibilityIdentifier("me.cardNumber")
            }
            if let worn = face.board.wornTitle {
                Capsule()
                    .fill(TitleBadgeView.enamel(worn.badge.colour))
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
            if let squad = face.squadName {
                Text(squad)
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
                    .lineLimit(1)
                    .accessibilityIdentifier("me.squadName")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stats: some View {
        HStack(alignment: .top, spacing: Space.xs) {
            FrontStat(label: Text("练了", bundle: .module)) {
                Score(count: face.counts.trainedDays, size: .card, onInk: true)
                    .accessibilityIdentifier("me.trainedDays")
            }
            if let week = face.week {
                FrontStat(label: Text("本周", bundle: .module)) {
                    Score(count: week.trainedDays, goal: week.plannedDays, size: .card, onInk: true)
                }
            }
            FrontStat(label: Text("徽章", bundle: .module)) {
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
/// it, then the badge board, three to a row, ending on the dashed slot of the next Sunday's.
private struct CardBack: View {
    let face: PlayerCardFace
    let open: (BoardTitle) -> Void
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(face.character.nickname)
                    .typeStyle(TypeRamp.headline)
                    .foregroundStyle(Color(role: .fgOnInk, in: theme))
                    .lineLimit(1)
                Spacer(minLength: Space.s)
                if let number = face.number {
                    Text(verbatim: "#\(number.text)")
                        .typeStyle(TypeRamp.scoreSmall)
                        .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
                        .monospacedDigit()
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: Space.xs) {
                Score(count: face.counts.trainedDays, size: .hero, onInk: true)
                Text("card.career \(face.counts.healthyMeals) \(face.counts.disclaimers)", bundle: .module)
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
                    // One line, shrunk to fit, so a word never breaks across lines.
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.top, Space.xs)
            .accessibilityElement(children: .combine)
            HStack(alignment: .firstTextBaseline) {
                Text("徽章", bundle: .module)
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
            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: Space.s) {
                    ForEach(face.board.titles) { title in
                        Button {
                            open(title)
                        } label: {
                            BadgeCell(title: title, isWorn: face.board.worn == title.title)
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityIdentifier("me.badge")
                    }
                    NextBadgeCell()
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

/// The card window's faint court: a boundary inset from the window's edge, a half line behind
/// the character's middle and a centre circle on it. The card's only backdrop for now; more can
/// come later as backdrops a member unlocks.
private struct CourtLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let court = rect.insetBy(dx: Space.s, dy: Space.s)
        path.addRoundedRect(in: court, cornerSize: CGSize(width: Space.xxs, height: Space.xxs))
        let halfLine = rect.minY + rect.height * 0.7
        path.move(to: CGPoint(x: court.minX, y: halfLine))
        path.addLine(to: CGPoint(x: court.maxX, y: halfLine))
        let radius = rect.width * 0.22
        path.addEllipse(
            in: CGRect(x: rect.midX - radius, y: halfLine - radius, width: radius * 2, height: radius * 2)
        )
        return path
    }
}
#endif
