#if os(iOS)
import CheckInDomain
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The coach's empty spot on the sideline while the squad has no coach (approved 2026-11-08): a
/// dashed outline of a coach, as big as one, with 「招聘教练」 under its feet. A tap opens 教练招聘会,
/// where the captain hires and everyone else browses; once a coach is hired, it stands here.
struct SidelineVacancy: View {
    /// Where its feet are, in stage points.
    let spot: StagePoint
    let unit: Double
    let tap: () -> Void
    @Environment(\.sceneTheme) private var theme

    /// The outline's height on the stage, as tall as a coach's body.
    private static let height = 250 * StageLayout.coachScale
    /// Its width against its height, a coach's silhouette's.
    private static let aspect = 0.5
    /// Its dashes.
    private static let dash = StrokeStyle(lineWidth: 2, dash: [5, 4])

    var body: some View {
        let height = Self.height * unit
        let width = height * Self.aspect
        VStack(spacing: Space.xs) {
            UnevenRoundedRectangle(
                topLeadingRadius: width / 2, bottomLeadingRadius: width * 0.09, bottomTrailingRadius: width * 0.09,
                topTrailingRadius: width / 2, style: .continuous
            )
            .strokeBorder(Color(role: .fgSubtle, in: theme), style: Self.dash)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: width / 2, bottomLeadingRadius: width * 0.09, bottomTrailingRadius: width * 0.09,
                    topTrailingRadius: width / 2, style: .continuous
                )
                .fill(Color(role: .bgCanvas, in: theme).opacity(0.45))
            )
            .frame(width: width, height: height)
            InkTag(Text("招聘教练", bundle: .module), height: CoachTag.Size.regular.height)
                .fixedSize()
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
        .position(x: spot.x * unit, y: spot.y * unit)
        // Its feet on the spot: the outline's bottom edge, the tag hanging under it.
        .offset(y: (Space.xs + CoachTag.Size.regular.height - height) / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("招聘教练", bundle: .module))
        .accessibilityIdentifier("today.coachVacancy")
        .accessibilityAddTraits(.isButton)
    }
}

extension SquadSceneView {
    /// How far into its drop the coach is at `date`, in seconds (below zero while it waits),
    /// or infinity once it stands, as it does whenever nobody is dropping in.
    func coachFall(at date: Date) -> Double {
        guard let arrival, !reduceMotion else { return .infinity }
        return arrival.coachFall(at: date)
    }
}

#endif
