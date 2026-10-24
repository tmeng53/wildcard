#if os(iOS)
import DesignSystem
import DesignSystemUI
import MeDomain
import SportsUI
import SwiftUI

/// 我's player card, like a baseball card: the front has the character, the name and squad and the
/// headline numbers; a tap turns it over to the career numbers, and two dots under it say which
/// side is up. Ink card stock with white type, the character in a light grey window.
struct PlayerCard: View {
    let overview: MeOverview
    @State private var showsBack = false
    /// How far the card has turned on its vertical axis, in degrees: it turns edge-on, swaps sides
    /// out of sight and turns back.
    @State private var turn: Double = 0
    @State private var isTurning = false
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let size = CGSize(width: 300, height: 460)

    var body: some View {
        VStack(spacing: Space.s) {
            Button(action: flip) {
                Group {
                    if showsBack {
                        CardBack(overview: overview)
                    } else {
                        CardFront(overview: overview)
                    }
                }
                .padding(Space.xs)
                .frame(width: Self.size.width, height: Self.size.height)
                .background(Color(role: .bgInk, in: theme), in: Self.shape)
                .contentShape(Self.shape)
                .rotation3DEffect(.degrees(turn), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityHint(Text("轻点翻面", bundle: .module))
            .accessibilityIdentifier("me.card")
            HStack(spacing: Space.xs) {
                Dot(isOn: !showsBack)
                Dot(isOn: showsBack)
            }
            .accessibilityHidden(true)
        }
    }

    private static let shape = RoundedRectangle(cornerRadius: Radius.card + Space.xxs, style: .continuous)

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

/// The front: the character in its window under the card's number and latest title, the name,
/// squad and the year they joined, then 练了, 本周 and 周奖.
private struct CardFront: View {
    let overview: MeOverview
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            MeStage(character: overview.character, floor: .borderDefault)
                .padding(.bottom, -Space.xxs)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .overlay(alignment: .top) {
                    // One row, so a long title gives way (truncating) before it can reach the number.
                    HStack(alignment: .top, spacing: Space.xs) {
                        if let number = overview.cardNumber {
                            Text(verbatim: number.text)
                                .typeStyle(TypeRamp.scoreHero)
                                .foregroundStyle(Color(role: .fgDefault, in: theme))
                                .monospacedDigit()
                                .fixedSize()
                                .padding(.leading, Space.s)
                                .padding(.top, Space.xs)
                                .accessibilityLabel(Text("card.number \(number.text)", bundle: .module))
                                .accessibilityIdentifier("me.cardNumber")
                        }
                        Spacer(minLength: 0)
                        if let latest = overview.titles.latest {
                            Text(verbatim: latest.title)
                                .typeStyle(TypeRamp.footnoteEmphasis)
                                .foregroundStyle(Color(role: .fgDefault, in: theme))
                                .lineLimit(1)
                                .padding(.horizontal, Space.xs)
                                .padding(.vertical, Space.xxs)
                                .background(Color(role: .bgCanvas, in: theme), in: Capsule())
                                .padding(.trailing, Space.xs)
                                .padding(.top, Space.s)
                                .accessibilityIdentifier("me.latestTitle")
                        }
                    }
                }
                .background(
                    Color(role: .bgSubtle, in: theme),
                    in: RoundedRectangle(cornerRadius: Radius.pick, style: .continuous)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.pick, style: .continuous))
            HStack(alignment: .lastTextBaseline, spacing: Space.xs) {
                nameAndSquad
                if let year = overview.joinedAt.map({ String(Calendar.current.component(.year, from: $0)) }) {
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

    private var nameAndSquad: some View {
        VStack(alignment: .leading, spacing: Space.xxs / 2) {
            Text(overview.character.nickname)
                .typeStyle(TypeRamp.title)
                .foregroundStyle(Color(role: .fgOnInk, in: theme))
                .lineLimit(1)
                .accessibilityIdentifier("me.nickname")
            if let squad = overview.squadName {
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
                Score(count: overview.counts.trainedDays, size: .card, onInk: true)
                    .accessibilityIdentifier("me.trainedDays")
            }
            if let week = overview.week {
                FrontStat(label: Text("本周", bundle: .module)) {
                    Score(count: week.trainedDays, goal: week.plannedDays, size: .card, onInk: true)
                }
            }
            FrontStat(label: Text("周奖", bundle: .module)) {
                Score(count: overview.titles.count, size: .card, onInk: true)
                    .accessibilityIdentifier("me.titles")
            }
        }
        .padding(.horizontal, Space.xxs)
        .padding(.top, Space.s)
        .padding(.bottom, Space.xxs)
        .overlay(alignment: .top) { Hairline().padding(.horizontal, Space.xxs) }
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

/// The back: the name and number, the career count of 练了 large, then every other kind, this
/// week, the sport trained most and the latest title.
private struct CardBack: View {
    let overview: MeOverview
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(overview.character.nickname)
                    .typeStyle(TypeRamp.headline)
                    .foregroundStyle(Color(role: .fgOnInk, in: theme))
                    .lineLimit(1)
                Spacer(minLength: Space.s)
                if let number = overview.cardNumber {
                    Text(verbatim: "#\(number.text)")
                        .typeStyle(TypeRamp.scoreInline)
                        .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
                        .monospacedDigit()
                }
            }
            Text("card.career", bundle: .module)
                .typeStyle(TypeRamp.label)
                .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
                .padding(.top, Space.m)
            HStack(alignment: .lastTextBaseline, spacing: Space.xs) {
                Score(count: overview.counts.trainedDays, size: .hero, onInk: true)
                Text("次练了", bundle: .module)
                    .typeStyle(TypeRamp.callout)
                    .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
            }
            .padding(.top, Space.xxs)
            VStack(spacing: 0) {
                BackStat(label: Text("健康餐", bundle: .module), isLast: false) {
                    Score(count: overview.counts.healthyMeals, size: .inline, onInk: true)
                }
                BackStat(label: Text("坦白放纵餐", bundle: .module), isLast: false) {
                    Score(count: overview.counts.cheatMeals, size: .inline, onInk: true)
                }
                BackStat(label: Text("请假条", bundle: .module), isLast: false) {
                    Score(count: overview.counts.disclaimers, size: .inline, onInk: true)
                }
                if let week = overview.week {
                    BackStat(label: Text("本周", bundle: .module), isLast: false) {
                        Score(count: week.trainedDays, goal: week.plannedDays, size: .inline, onInk: true)
                    }
                }
                if let most = overview.mostTrained {
                    BackStat(label: Text("最常练", bundle: .module), isLast: false) {
                        HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
                            most.activity.name
                                .typeStyle(TypeRamp.callout)
                                .foregroundStyle(Color(role: .fgOnInk, in: theme))
                                .lineLimit(1)
                            Score(count: most.checkIns, size: .inline, onInk: true)
                        }
                    }
                    .accessibilityIdentifier("me.mostTrained")
                }
                BackStat(label: Text("周奖", bundle: .module), isLast: true) {
                    if let latest = overview.titles.latest {
                        HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
                            Text(verbatim: latest.title)
                                .typeStyle(TypeRamp.callout)
                                .foregroundStyle(Color(role: .fgOnInk, in: theme))
                                .lineLimit(1)
                            Text(verbatim: "×\(latest.times)")
                                .typeStyle(TypeRamp.scoreInline)
                                .foregroundStyle(Color(role: .fgOnInk, in: theme))
                                .monospacedDigit()
                        }
                    } else {
                        Score(count: 0, size: .inline, onInk: true)
                    }
                }
                .accessibilityIdentifier("me.backTitles")
            }
            .padding(.top, Space.s)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.xs)
        .padding(.top, Space.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One line of the back: the kind on the left, its number on the right, a hairline under it.
private struct BackStat<Value: View>: View {
    let label: Text
    let isLast: Bool
    @ViewBuilder let value: Value
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            label
                .typeStyle(TypeRamp.body)
                .foregroundStyle(Color(role: .fgOnInk, in: theme))
            Spacer(minLength: Space.s)
            value
        }
        .padding(.vertical, Space.xs)
        .overlay(alignment: .bottom) {
            if !isLast { Hairline() }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The card's dividers: a hairline across.
private struct Hairline: View {
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(Color(role: .borderOnInk, in: theme))
            .frame(height: Sizing.hairline)
    }
}

/// Which side of the card is up: ink for this one, grey for the other.
private struct Dot: View {
    let isOn: Bool
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        Circle()
            .fill(Color(role: isOn ? .fgDefault : .borderDefault, in: theme))
            .frame(width: Space.xs - 2, height: Space.xs - 2)
    }
}
#endif
