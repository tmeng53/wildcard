#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import RecapDomain
import SwiftUI

/// What every page reads: its own clock and the story's cast and wardrobe.
struct PageContext {
    /// Seconds into the page.
    let time: Double
    /// False with Reduce Motion: everything shows where it ends up.
    let moves: Bool
    let story: WeekStory
    let cast: StoryCast
    let wardrobe: StoryWardrobe

    /// 0 before `start`, 1 after `end`, linear between; 1 when nothing moves.
    func ramp(_ start: Double, _ end: Double) -> Double {
        guard moves else { return 1 }
        return min(max((time - start) / (end - start), 0), 1)
    }

    /// `ramp`, overshooting a little before it settles: things that pop in.
    func pop(_ start: Double, _ end: Double) -> Double {
        let fraction = ramp(start, end)
        // Back-out easing, as the design's `backOut`.
        let overshoot = 1.70158
        let shifted = fraction - 1
        return 1 + (overshoot + 1) * shifted * shifted * shifted + overshoot * shifted * shifted
    }

    /// Who stands in a lineup: the people the story names, then everyone else in the squad.
    var lineup: [MemberID] {
        let named = story.cast.filter { cast[$0] != nil }
        let others = cast.members.values.filter { !named.contains($0.id) }.sorted { $0.nickname < $1.nickname }
        return named + others.map(\.id)
    }

    func character(
        _ member: MemberID, act: Act = Act(), regalia: Regalia = .none, prop: String? = nil
    ) -> StoryCharacter {
        StoryCharacter(wardrobe: wardrobe, member: member, act: act, regalia: regalia, prop: prop, time: time)
    }
}

/// A page's label and title, on the scene: 「本周 / 领奖台」.
struct PageTitle: View {
    let label: Text
    var systemImage: String?
    let title: Text
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack(spacing: Space.xxs) {
                if let systemImage {
                    Image(systemName: systemImage).accessibilityHidden(true)
                }
                label
            }
            .typeStyle(TypeRamp.label)
            title
                .typeStyle(TypeRamp.largeTitle)
                .accessibilityAddTraits(.isHeader)
        }
        .foregroundStyle(Color(role: .fgOnScene, in: theme))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.l)
        .padding(.top, StoryLayout.titleTop)
        .accessibilityElement(children: .combine)
    }
}

/// The white ground the squad stands on, along the bottom of a page.
struct Ground: View {
    let height: Double
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Color(role: .bgCanvas, in: theme)
                .frame(height: height)
        }
        .ignoresSafeArea(edges: .bottom)
        .accessibilityHidden(true)
    }
}

/// The podium under its cloth: nobody's place shows. The pending page and the feed's tile.
struct CoveredPodium: View {
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        ZStack {
            PodiumBlocks().fill(Color(role: .bgCanvas, in: theme))
            Cloth().fill(Color(role: .bgAccent, in: theme))
            ClothFolds().stroke(
                Color(role: .fgOnAccent, in: theme).opacity(0.28),
                style: StrokeStyle(lineWidth: 3 * StoryLayout.clothStroke, lineCap: .round))
        }
        .aspectRatio(360 / 150, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// The design draws the cloth on a 360 by 150 box.
    private static func point(_ across: Double, _ down: Double, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + across / 360 * rect.width, y: rect.minY + down / 150 * rect.height)
    }

    private struct PodiumBlocks: Shape {
        func path(in rect: CGRect) -> Path {
            let spot = { (across: Double, down: Double) in CoveredPodium.point(across, down, in: rect) }
            var path = Path()
            path.move(to: spot(8, 150))
            path.addLine(to: spot(8, 62))
            path.addLine(to: spot(116, 62))
            path.addLine(to: spot(116, 10))
            path.addLine(to: spot(244, 10))
            path.addLine(to: spot(244, 62))
            path.addLine(to: spot(352, 62))
            path.addLine(to: spot(352, 150))
            path.closeSubpath()
            return path
        }
    }

    private struct Cloth: Shape {
        func path(in rect: CGRect) -> Path {
            let spot = { (across: Double, down: Double) in CoveredPodium.point(across, down, in: rect) }
            var path = Path()
            path.move(to: spot(4, 66))
            path.addQuadCurve(to: spot(12, 58), control: spot(4, 58))
            path.addLine(to: spot(112, 58))
            path.addQuadCurve(to: spot(128, 6), control: spot(118, 6))
            path.addLine(to: spot(232, 6))
            path.addQuadCurve(to: spot(248, 58), control: spot(242, 6))
            path.addLine(to: spot(348, 58))
            path.addQuadCurve(to: spot(356, 66), control: spot(356, 58))
            path.addLine(to: spot(352, 132))
            // The hem: a soft wave back to the left.
            var edge = 352.0
            var rising = true
            while edge > 8 {
                let next = max(edge - 24, 8)
                path.addQuadCurve(to: spot(next, 132), control: spot((edge + next) / 2, rising ? 120 : 144))
                rising.toggle()
                edge = next
            }
            path.closeSubpath()
            return path
        }
    }

    private struct ClothFolds: Shape {
        func path(in rect: CGRect) -> Path {
            let spot = { (across: Double, down: Double) in CoveredPodium.point(across, down, in: rect) }
            var path = Path()
            for (top, control, bottom) in [
                ((128.0, 6.0), (150.0, 60.0), (140.0, 128.0)), ((232, 6), (212, 60), (222, 128)),
                ((40, 60), (52, 96), (44, 128)), ((320, 60), (306, 96), (316, 128)),
            ] {
                path.move(to: spot(top.0, top.1))
                path.addQuadCurve(to: spot(bottom.0, bottom.1), control: spot(control.0, control.1))
            }
            return path
        }
    }
}

/// A count of one reaction kind, as the feed shows it: its word and a Barlow number.
struct ReactionChip: View {
    let reaction: ReactionCount
    let isFirst: Bool
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        HStack(spacing: Space.xxs) {
            Text(verbatim: reaction.label).typeStyle(isFirst ? TypeRamp.calloutEmphasis : TypeRamp.callout)
            Text(verbatim: "\(reaction.count)").typeStyle(TypeRamp.scoreSmall)
        }
        .foregroundStyle(Color(role: isFirst ? .fgAccent : .fgDefault, in: theme))
        .padding(.horizontal, Space.s)
        .frame(height: Sizing.tag + Space.xs)
        .background(Color(role: isFirst ? .bgAccentSubtle : .bgSubtle, in: theme), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// The medal beside a title, in the scene's accent.
struct MedalMark: View {
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        Image(systemName: "medal.fill")
            .font(.system(size: Sizing.icon))
            .foregroundStyle(Color(role: .fgAccent, in: theme))
            .accessibilityHidden(true)
    }
}

/// Where the story's shared pieces sit, from the approved v6 design (a 390 by 844 phone).
enum StoryLayout {
    /// The page title's top, under the segments and the header.
    static let titleTop: Double = 112
    /// The cloth's fold lines, at the design's width.
    static let clothStroke: Double = 1
    /// How tall the white ground is on each kind of page.
    static let groundLow: Double = 150
    static let groundMeals: Double = 190
    static let groundEnding: Double = 214
    static let groundWeek: Double = 224
}

extension Week {
    /// 「10.13 – 10.19」.
    var label: String {
        "\(monday.month).\(monday.day) – \(sunday.month).\(sunday.day)"
    }
}
#endif
