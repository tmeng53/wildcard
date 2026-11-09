#if os(iOS)
import AvatarDomain
import AvatarUI
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The squad's coach standing on the sideline, as big as me, idling; it has no ring, since it
/// doesn't check in. It drops in after the squad onto a newly picked scene. While its page has a
/// card not seen yet, the phone in its hand shows the unread dot, and the home has it whistle
/// again and again (Tracy, 2026-11-09; under Reduce Motion, the dot only).
struct SidelineCoachFigure: View {
    let coach: SquadCast.Coach
    let unit: Double
    let date: Date
    let reduceMotion: Bool
    /// How far above its spot it is, in stage points, while it drops in.
    var lift: Double = 0
    /// Whether its page has a card not seen yet.
    var hasNews = false
    /// How far right of its spot it is, in stage points, and how far it leans, in degrees, while
    /// the coaches change places (换教练).
    var shift: Double = 0
    var tilt: Double = 0

    /// Members' canvas, which coaches share, and where its feet are on it.
    static let canvas = CGSize(width: 240, height: 320)
    static let feet = CGPoint(x: 120, y: 316)
    /// The room above the canvas its cheer's hop reaches into, in rig points.
    private static let reach = CGRect(x: 0, y: -60, width: 240, height: 380)
    /// The part holding the phone, and the phone's top corner on its art, where the dot sits.
    private static let phoneHand: PartID = "armR"
    private static let phoneCorner = Point(x: 160, y: 179)
    /// The dot, and the ring around it, as on 动态's bell, in points.
    private static let dot: Double = 8
    private static let dotRing: Double = 2

    var body: some View {
        let scale = coach.scale * unit
        let frame = reduceMotion ? coach.player.restFrame : coach.player.frame(at: date)
        Color.clear
            .overlay {
                CharacterCanvas(drawing: frame.drawing, placements: frame.placements, crop: Self.reach)
                    .frame(width: Self.reach.width * scale, height: Self.reach.height * scale)
                    .offset(y: (Self.reach.midY - Self.canvas.height / 2) * scale)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                if hasNews, let corner = phoneCorner(frame.placements) {
                    unreadDot
                        .position(x: corner.x * scale, y: corner.y * scale)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.wildcard(Motion.celebrate, reduceMotion: reduceMotion), value: hasNews)
            .rotationEffect(.degrees(tilt))
            .offset(y: -lift * unit)
            .frame(width: Self.canvas.width * scale, height: Self.canvas.height * scale)
            .contentShape(Rectangle())
            .position(
                x: (coach.spot.x + shift) * unit,
                y: coach.spot.y * unit - (Self.feet.y - Self.canvas.height / 2) * scale)
    }

    /// The phone's top corner on the canvas this frame, as the hand holding it moves; nil for a
    /// coach whose art holds no phone.
    private func phoneCorner(_ placements: [Placement]) -> Point? {
        guard let hand = coach.player.figure.parts.firstIndex(where: { $0.id == Self.phoneHand }),
            placements.indices.contains(hand)
        else { return nil }
        return placements[hand].transform.apply(to: Self.phoneCorner)
    }

    /// The unread dot on the phone.
    private var unreadDot: some View {
        Circle()
            .fill(Color(role: .bgBrand, in: .gym))
            .frame(width: Self.dot, height: Self.dot)
            .padding(Self.dotRing)
            .background(Circle().fill(Color(role: .bgCanvas, in: .gym)))
            .accessibilityHidden(true)
    }
}

/// The coach on the sideline as a button by its name, for VoiceOver and UI tests, saying whether
/// something waits; it tells where it stands on screen, for its letter to fly from.
struct SidelineCoachButton: ViewModifier {
    let name: String
    let hasNews: Bool
    let tap: () -> Void
    let standsAt: (CGPoint) -> Void

    func body(content: Content) -> some View {
        content
            .onTapGesture(perform: tap)
            .onGeometryChange(for: CGPoint.self) { proxy in
                let frame = proxy.frame(in: .global)
                return CGPoint(x: frame.midX, y: frame.midY)
            } action: {
                standsAt($0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: name))
            .accessibilityValue(hasNews ? Text(copy: "有新消息", bundle: .module) : Text(verbatim: ""))
            .accessibilityIdentifier("today.coach")
            .accessibilityAddTraits(.isButton)
    }
}

extension SquadSceneView {
    /// The squad's coach on the sideline, or the two changing places there (换教练).
    @ViewBuilder
    func sidelineCoach(unit: Double, date: Date) -> some View {
        if let handover = cast.handover, let incoming = cast.incoming {
            CoachHandoverFigures(
                handover: handover, outgoing: cast.coach, incoming: incoming, unit: unit, date: date,
                moment: reduceMotion ? .distantFuture : clock(), reduceMotion: reduceMotion)
        } else if let coach = cast.coach, case let fall = coachFall(at: date), fall >= 0 {
            // The coach drops in last, after me; under Reduce Motion it is simply there.
            SidelineCoachFigure(
                coach: coach, unit: unit, date: date, reduceMotion: reduceMotion,
                lift: DropIn.lift(at: fall, spotY: coach.spot.y, clipLift: 0), hasNews: coachHasNews
            )
            .modifier(
                SidelineCoachButton(
                    name: coach.speaker.name, hasNews: coachHasNews, tap: tapCoach, standsAt: coachAt)
            )
            .zIndex(coach.spot.y)
        }
    }

    /// How far into its drop the coach is at `date`, in seconds (below zero while it waits),
    /// or infinity once it stands, as it does whenever nobody is dropping in.
    func coachFall(at date: Date) -> Double {
        guard let arrival, !reduceMotion else { return .infinity }
        return arrival.coachFall(at: date)
    }
}
#endif
