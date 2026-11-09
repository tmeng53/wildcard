#if os(iOS)
import CheckInDomain
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The coaches changing places on the sideline (换教练), by `CoachHandover`'s timeline: the coach
/// that left writing on its spot under 「交接中」, then walking off to the left; the one that took
/// over walking in, waiting beside it, then stepping onto the spot. Neither is tapped meanwhile.
struct CoachHandoverFigures: View {
    let handover: CoachHandover
    /// The coach that left; nil for one this build has no character for.
    let outgoing: SquadCast.Coach?
    let incoming: SquadCast.Coach
    let unit: Double
    /// The display frame's time, which the characters' clips play by.
    let date: Date
    /// The home's clock, which the handover plays by.
    let moment: Date
    let reduceMotion: Bool

    /// Where the top of a coach's canvas is above its feet, in rig points (`SidelineCoachFigure`'s).
    private static let canvasTop = 316.0

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let outgoing, handover.showsOutgoing(at: moment) {
                let walk = handover.outgoing(at: moment)
                let scribble = reduceMotion ? (lift: 0, degrees: 0) : handover.scribble(at: moment)
                SidelineCoachFigure(
                    coach: outgoing, unit: unit, date: date, reduceMotion: reduceMotion,
                    lift: walk.lift + scribble.lift, shift: walk.dx, tilt: scribble.degrees)
                let chip = handover.chip(at: moment)
                Color.clear
                    .frame(width: 1, height: 1)
                    .overlay(alignment: .bottom) {
                        HandoverChip()
                            .fixedSize()
                            .opacity(chip)
                            .accessibilityHidden(chip < 0.5)
                    }
                    .position(
                        x: (outgoing.spot.x + walk.dx) * unit,
                        y: (outgoing.spot.y - Self.canvasTop * outgoing.scale - walk.lift) * unit)
            }
            SidelineCoachFigure(
                coach: incoming, unit: unit, date: date, reduceMotion: reduceMotion,
                shift: handover.incoming(at: moment, sideline: incoming.spot)
            )
            .accessibilityHidden(true)
        }
        .allowsHitTesting(false)
        .zIndex(incoming.spot.y)
    }
}

/// 「交接中」 over the coach writing its letter, with the dots that say it is under way.
private struct HandoverChip: View {
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: Space.xxs / 2) {
            Text("交接中", bundle: .module)
                .typeStyle(TypeRamp.footnoteEmphasis)
            // The prototype's dots, half the size of a line's.
            LoadingDots(delay: 0)
                .scaleEffect(0.5)
                .frame(width: Loading.dotsWidth / 2, height: (Loading.dot + Loading.dotRise) / 2)
        }
        .foregroundStyle(Color(role: .fgDefault, in: theme))
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xxs)
        .background(Capsule().fill(Color(role: .bgCanvas, in: theme)))
        .shadow(color: Color(role: .bgBrand, in: theme).opacity(0.15), radius: 4, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("交接中", bundle: .module))
        .accessibilityIdentifier("today.handover")
    }
}
#endif
