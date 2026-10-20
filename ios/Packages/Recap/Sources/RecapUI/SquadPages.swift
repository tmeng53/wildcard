#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import RecapDomain
import SwiftUI

/// 吃了: the squad's meals, and everyone eating what they logged more of. Never a judgment of
/// food or bodies.
struct MealsPage: View {
    let meals: Meals
    let page: PageContext
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let floor = proxy.size.height - StoryLayout.groundMeals
            let eaters = Array(meals.eaters.filter { page.cast[$0.member] != nil }.prefix(8))
            let spacing = (width - 2 * Space.l) / Double(max(eaters.count, 1))
            ZStack(alignment: .topLeading) {
                Ground(height: StoryLayout.groundMeals)
                ForEach(Array(eaters.enumerated()), id: \.element.member) { index, eater in
                    page.character(
                        eater.member,
                        act: Act(
                            clip: .eat(eater.more), start: 0.3 + Self.offsets[index % Self.offsets.count],
                            seed: Double(index) * 0.41)
                    )
                    .standing(
                        feetAt: CGPoint(
                            x: Space.l + spacing * (Double(index) + 0.5), y: floor + Space.xl + Double(index % 2) * 14),
                        scale: 0.4)
                }
            }
        }
        .overlay(alignment: .top) {
            VStack(alignment: .leading, spacing: Space.l) {
                PageTitle(label: Text("全队", bundle: .module), title: Text("吃了", bundle: .module))
                HStack(alignment: .top, spacing: Space.xl) {
                    count(meals.healthy, Text("健康餐", bundle: .module), size: .story)
                    count(meals.cheat, Text("坦白放纵餐", bundle: .module), size: .hero)
                }
                if let line = meals.line {
                    Text(verbatim: line)
                        .typeStyle(TypeRamp.headline)
                        .opacity(page.ramp(0.6, 0.9))
                }
            }
            .foregroundStyle(Color(role: .fgOnScene, in: theme))
            .padding(.horizontal, Space.l)
        }
    }

    /// Eaters don't start in step.
    private static let offsets = [0, 0.5, 0.2, 0.7, 0.35]

    private func count(_ value: Int, _ label: Text, size: Score.Size) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Score(count: value, size: size)
            label.typeStyle(TypeRamp.footnote)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 最佳请假条: the note, its author acting it out (the AI picks how), two teammates reacting.
struct BestDisclaimerPage: View {
    let note: BestDisclaimer
    let page: PageContext
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let floor = proxy.size.height - StoryLayout.groundLow
            let teammates = Array(page.lineup.filter { $0 != note.author }.prefix(2))
            ZStack(alignment: .topLeading) {
                Ground(height: StoryLayout.groundLow)
                ForEach(Array(teammates.enumerated()), id: \.element) { index, member in
                    page.character(
                        member,
                        act: Act(
                            clip: .award((note.squadMove ?? .laugh).solo), start: 1.3 + Double(index) * 0.2,
                            seed: Double(index) * 0.4)
                    )
                    .standing(feetAt: CGPoint(x: index == 0 ? 50 : width - 40, y: floor + 6), scale: 0.44)
                }
                page.character(
                    note.author, act: Act(clip: .award((note.authorMove ?? .flat).solo), start: 0.5, hold: 3.2)
                )
                .standing(feetAt: CGPoint(x: width * 0.58, y: floor), scale: 0.56)
            }
        }
        .overlay(alignment: .top) {
            VStack(alignment: .leading, spacing: Space.l) {
                PageTitle(
                    label: Text("本周", bundle: .module), systemImage: "bubble.left.fill",
                    title: Text("最佳请假条", bundle: .module))
                card
                    .padding(.horizontal, Space.m)
                    .offset(y: 24 * (1 - page.pop(0, 0.5)))
                    .opacity(page.ramp(0, 0.2))
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text(verbatim: note.text)
                .typeStyle(TypeRamp.taskTitle)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Space.s) {
                Text(verbatim: page.cast.nickname(of: note.author))
                    .typeStyle(TypeRamp.calloutEmphasis)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                Spacer(minLength: 0)
                Text("\(note.reactions) 个回应", bundle: .module)
                    .typeStyle(TypeRamp.callout)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
            }
        }
        .padding(.vertical, Space.xs)
        .card(on: .scene)
        .accessibilityElement(children: .combine)
    }
}

/// 这一周: the squad's training days against its plans, the AI's headline and line, and its
/// finale. Never red, never guilt. 存图 and 排下周 wait here.
struct EndingPage: View {
    let ending: Ending
    let page: PageContext
    let actions: EndingActions?
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let floor = proxy.size.height - StoryLayout.groundEnding
            let lineup = Array(page.lineup.prefix(8))
            ZStack(alignment: .topLeading) {
                Ground(height: StoryLayout.groundEnding)
                finale(lineup, width: width, floor: floor + Space.xs)
                if let actions {
                    VStack(spacing: Space.xs) {
                        if let picture = actions.picture {
                            ShareLink(
                                item: picture,
                                preview: SharePreview(Text("本周战报", bundle: .module), image: picture)
                            ) {
                                Text("存图", bundle: .module).frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PrimaryButtonStyle(.large))
                            .accessibilityIdentifier("recap.save")
                        }
                        Button(action: actions.planNextWeek) { Text("排下周", bundle: .module) }
                            .buttonStyle(TextButtonStyle(.muted))
                            .accessibilityIdentifier("recap.planNextWeek")
                    }
                    .padding(.horizontal, Space.m)
                    .frame(width: width)
                    .position(x: width / 2, y: proxy.size.height - StoryLayout.groundEnding / 2 + Space.l)
                }
            }
        }
        .overlay(alignment: .top) {
            VStack(alignment: .leading, spacing: Space.l) {
                PageTitle(label: Text("全队", bundle: .module), title: headline)
                VStack(alignment: .leading, spacing: Space.s) {
                    Score(count: Int((Double(ending.done) * counted).rounded()), goal: ending.plan, size: .story)
                    line.typeStyle(TypeRamp.headline)
                    ProgressBar(fraction: ending.fraction * counted)
                }
                .foregroundStyle(Color(role: .fgOnScene, in: theme))
                .padding(.horizontal, Space.l)
            }
        }
    }

    /// The count and bar fill over the first second.
    private var counted: Double {
        let fraction = page.ramp(0.1, 1.0)
        return 1 - (1 - fraction) * (1 - fraction)
    }

    private var headline: Text {
        ending.headline.map { Text(verbatim: $0) } ?? Text("这一周", bundle: .module)
    }

    private var line: Text {
        if let line = ending.line { return Text(verbatim: line) }
        return ending.isHit ? Text("全队达标", bundle: .module) : Text("还差 \(ending.shortBy) 次", bundle: .module)
    }

    @ViewBuilder
    private func finale(_ lineup: [MemberID], width: Double, floor: Double) -> some View {
        let move = ending.finale(castSize: lineup.count)
        let spacing = (width - 2 * Space.l) / Double(max(lineup.count, 1))
        let spot = { (index: Int) in Space.l + spacing * (Double(index) + 0.5) }
        if move == .stack, let pair = stackPair(lineup) {
            ForEach(Array(lineup.enumerated()), id: \.element) { index, member in
                if member == pair.top {
                    // Carried: stands on the bottom one's shoulders, settling as the clip lands.
                    page.character(member, act: Act(clip: .stackTop, start: 0.9, hold: 2.1))
                        .standing(
                            feetAt: CGPoint(
                                x: spot(pair.bottomIndex) - Self.stackReach * Self.scale,
                                y: floor + 10 * page.ramp(1.56, 1.68)),
                            scale: Self.scale
                        )
                        .zIndex(1)
                } else if member == pair.bottom {
                    page.character(member, act: Act(clip: .stackBottom, start: 0.9, hold: 2.1))
                        .standing(feetAt: CGPoint(x: spot(index), y: floor), scale: Self.scale)
                } else {
                    page.character(
                        member,
                        act: Act(
                            clip: .award(index % 2 == 0 ? .pump : .wave), start: 1.7 + Double(index) * 0.1,
                            seed: Double(index) * 0.41)
                    )
                    .standing(feetAt: CGPoint(x: spot(index), y: floor), scale: Self.scale)
                }
            }
        } else {
            ForEach(Array(lineup.enumerated()), id: \.element) { index, member in
                page.character(
                    member,
                    act: Act(clip: .award(move.solo), start: 0.8 + Double(index % 4) * 0.1, seed: Double(index) * 0.41)
                )
                .standing(feetAt: CGPoint(x: spot(index), y: floor), scale: Self.scale)
            }
        }
    }

    private static let scale = 0.42
    /// How far left of the carrier the stack's top clip starts, in canvas points.
    private static let stackReach = 150.0

    /// 叠罗汉: the champion carries the shyest teammate (or the last in line).
    private func stackPair(_ lineup: [MemberID]) -> (bottom: MemberID, bottomIndex: Int, top: MemberID)? {
        guard lineup.count >= 2 else { return nil }
        let bottom = page.story.podium?.champion ?? lineup[0]
        guard let bottomIndex = lineup.firstIndex(of: bottom) else { return nil }
        let others = lineup.filter { $0 != bottom }
        let top = others.first { page.cast[$0]?.persona == .shy } ?? others[others.count - 1]
        return (bottom, bottomIndex, top)
    }
}

/// What the last page offers: the page as a picture to save or post, and planning next week.
struct EndingActions {
    /// Nil until it is drawn, a moment after the page opens.
    let picture: Image?
    let planNextWeek: () -> Void
}
#endif
