#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import RecapDomain
import SwiftUI

/// 领奖台: the side-step winners toss the champion up, the crown lands on the way up, then the
/// medals and each one's move. Each step carries the member's first title.
struct PodiumPage: View {
    let podium: Podium
    let page: PageContext
    @Environment(\.sceneTheme) private var theme

    /// When the toss starts, and when the crown lands on the champion's head.
    static let toss = 0.8
    static let crownFalls = toss + 0.3
    static let crownLands = toss + 0.85
    /// When the toss is over and the medals are on.
    static let awarded = toss + 2.2

    private struct Step {
        let member: MemberID
        let height: Double
        let delay: Double
        let isChampion: Bool
    }

    private var steps: [(slot: Int, step: Step)] {
        var steps = [(slot: 1, step: Step(member: podium.champion, height: 150, delay: 0.16, isChampion: true))]
        for (index, side) in podium.sides.enumerated() {
            steps.append(
                (
                    slot: index == 0 ? 0 : 2,
                    step: Step(member: side, height: 96, delay: index == 0 ? 0 : 0.08, isChampion: false)
                ))
        }
        return steps
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let base = proxy.size.height - StoryLayout.groundLow
            let stepWidth = (width - 2 * Space.s - 2 * Space.xs) / 3
            ZStack(alignment: .topLeading) {
                Ground(height: StoryLayout.groundLow)
                ForEach(steps, id: \.step.member) { slot, step in
                    let rise = page.pop(step.delay, step.delay + 0.55)
                    let top = base - step.height * rise
                    let centre = Space.s + stepWidth / 2 + Double(slot) * (stepWidth + Space.xs)
                    stepBlock(step, width: stepWidth, rise: rise)
                        .position(x: centre, y: base - step.height * rise / 2)
                    character(step, index: slot)
                        .opacity(page.ramp(step.delay, step.delay + 0.12))
                        .standing(feetAt: CGPoint(x: centre, y: top), scale: 0.56)
                }
                if let speech = podium.speech {
                    Text(verbatim: "「\(speech)」")
                        .typeStyle(TypeRamp.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .frame(width: width - 2 * Space.xl)
                        .position(x: width / 2, y: base + StoryLayout.groundLow / 3)
                        .opacity(page.ramp(Self.awarded + 0.1, Self.awarded + 0.4))
                }
            }
        }
        .overlay(alignment: .top) {
            PageTitle(
                label: Text("本周", bundle: .module), systemImage: "checkmark.seal.fill",
                title: Text("领奖台", bundle: .module))
        }
        .haptic(.crown, trigger: page.time >= Self.crownLands) { old, new in !old && new }
    }

    private func stepBlock(_ step: Step, width: Double, rise: Double) -> some View {
        VStack(spacing: 0) {
            Text(verbatim: page.story.firstTitle(of: step.member) ?? "")
                .typeStyle(TypeRamp.calloutEmphasis)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
            Text(verbatim: page.cast.nickname(of: step.member))
                .typeStyle(TypeRamp.callout)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.top, Space.s)
        .frame(width: width, height: step.height, alignment: .top)
        .background(
            Color(role: .bgCanvas, in: theme),
            in: UnevenRoundedRectangle(
                topLeadingRadius: Radius.card, topTrailingRadius: Radius.card, style: .continuous)
        )
        .scaleEffect(x: 1, y: max(rise, 0.001), anchor: .bottom)
        .accessibilityElement(children: .combine)
    }

    private func character(_ step: Step, index: Int) -> StoryCharacter {
        let seed = Double(index) * 0.37
        let medal = page.time >= Self.awarded
        if step.isChampion {
            let fall = page.ramp(Self.crownFalls, Self.crownLands)
            let regalia = Regalia(medal: medal || !page.moves, crown: fall * fall)
            let act =
                page.time < Self.awarded
                ? Act(clip: .tossFlyer, start: Self.toss)
                : Act(clip: .award((podium.championMove ?? .pose).solo), start: Self.awarded, hold: 1.2)
            return page.character(step.member, act: act, regalia: regalia)
        }
        let act =
            page.time < Self.awarded
            ? Act(clip: .tossThrower, start: Self.toss, seed: seed)
            : Act(clip: .award((podium.sideMove ?? .pump).solo), start: Self.awarded + 0.1 + seed / 6, seed: seed)
        return page.character(step.member, act: act, regalia: Regalia(medal: medal || !page.moves))
    }
}

/// 本周头衔: every member's first title and its 颁奖词; each one does the move the AI picked as
/// its row lands.
struct TitlesPage: View {
    let rows: [MemberTitles]
    let page: PageContext
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            PageTitle(label: Text("本周", bundle: .module), title: Text("头衔", bundle: .module))
            VStack(spacing: Space.xs) {
                ForEach(Array(rows.enumerated()), id: \.element.member) { index, row in
                    let start = 0.15 + Double(index) * 0.3
                    let landed = page.pop(start, start + 0.45)
                    titleRow(row, index: index, start: start)
                        .offset(x: 40 * (1 - landed))
                        .opacity(page.ramp(start, start + 0.15))
                }
            }
            .padding(.horizontal, Space.m)
            Spacer(minLength: 0)
        }
    }

    private func titleRow(_ row: MemberTitles, index: Int, start: Double) -> some View {
        let first = row.titles.first
        return HStack(spacing: Space.s) {
            page.character(
                row.member,
                act: Act(clip: .award((first?.move ?? .cheer).solo), start: start + 0.35, seed: Double(index) * 0.3)
            )
            .frame(width: Sizing.characterHead * 2, height: Sizing.characterHead * 2.4)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(verbatim: row.titles.map(\.title).joined(separator: " · "))
                    .typeStyle(TypeRamp.headline)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                Text(
                    verbatim: [page.cast.nickname(of: row.member), first?.speech].compactMap { $0 }.joined(
                        separator: " · ")
                )
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            MedalMark()
        }
        .padding(.vertical, -Space.xxs)
        .card(on: .scene)
        .accessibilityElement(children: .combine)
    }
}

/// The titles are late: the organizers ran out of money. The squad dozes while the reader can
/// nudge them, once; the rest of the story plays as usual.
struct PendingPage: View {
    let page: PageContext
    let nudged: Bool
    let nudge: () -> Void
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let floor = proxy.size.height - StoryLayout.groundLow
            let lineup = Array(page.lineup.prefix(8))
            let spacing = (width - 2 * Space.l) / Double(max(lineup.count, 1))
            ZStack(alignment: .topLeading) {
                Ground(height: StoryLayout.groundLow)
                ForEach(Array(lineup.enumerated()), id: \.element) { index, member in
                    page.character(
                        member,
                        act: Act(clip: .award(.doze), start: 0.4 + Double(index) * 0.25, seed: Double(index) * 0.4)
                    )
                    .standing(feetAt: CGPoint(x: Space.l + spacing * (Double(index) + 0.5), y: floor), scale: 0.36)
                }
            }
        }
        .overlay(alignment: .top) {
            VStack(alignment: .leading, spacing: Space.l) {
                PageTitle(label: Text("本周", bundle: .module), title: Text("头衔", bundle: .module))
                VStack(alignment: .leading, spacing: Space.m) {
                    Text("主办方没经费了，正在拉赞助，一会儿再来颁奖", bundle: .module)
                        .typeStyle(TypeRamp.title)
                        .foregroundStyle(Color(role: .fgOnScene, in: theme))
                    if nudged {
                        Text("已催主办方充值 token", bundle: .module)
                            .typeStyle(TypeRamp.calloutEmphasis)
                            .foregroundStyle(Color(role: .fgOnScene, in: theme))
                            .transition(.opacity)
                    } else {
                        Button(action: nudge) { Text("催一下主办方", bundle: .module) }
                            .buttonStyle(PrimaryButtonStyle(.regular))
                            .accessibilityIdentifier("recap.nudge")
                    }
                }
                .animation(.wildcard(Motion.change, reduceMotion: !page.moves), value: nudged)
                .padding(.horizontal, Space.l)
            }
        }
        .haptic(.pick, trigger: nudged)
    }
}
#endif
