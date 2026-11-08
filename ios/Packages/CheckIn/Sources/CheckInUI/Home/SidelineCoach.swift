#if os(iOS)
import AvatarDomain
import AvatarUI
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The squad's coach standing on the sideline, as big as me, idling; it has no ring, since it
/// doesn't check in. It drops in after the squad onto a newly picked scene. While a morning note
/// waits, the phone in its hand shows the unread dot and buzzes, and it glances down at it (the
/// approved 毛头的手机来消息; under Reduce Motion, the dot only).
struct SidelineCoachFigure: View {
    let coach: SquadCast.Coach
    let unit: Double
    let date: Date
    let reduceMotion: Bool
    /// How far above its spot it is, in stage points, while it drops in.
    var lift: Double = 0
    /// Whether a morning note waits unread.
    var hasNote = false

    /// Members' canvas, which coaches share, and where its feet are on it.
    static let canvas = CGSize(width: 240, height: 320)
    static let feet = CGPoint(x: 120, y: 316)
    /// The room above the canvas its cheer's hop reaches into, in rig points.
    private static let reach = CGRect(x: 0, y: -60, width: 240, height: 380)
    /// The part holding the phone, and the phone's top corner on its art, where the dot sits.
    private static let phoneHand: PartID = "armR"
    private static let phoneCorner = Point(x: 160, y: 179)
    /// The dot, and the ring around it, as on 动态's bell; the buzz lines, in points.
    private static let dot: Double = 8
    private static let dotRing: Double = 2
    private static let buzzLine = CGSize(width: 2, height: 6)

    var body: some View {
        let scale = coach.scale * unit
        let frame = reduceMotion ? coach.player.restFrame : coach.player.frame(at: date)
        let seconds = date.timeIntervalSinceReferenceDate
        let buzzes = hasNote && !reduceMotion
        Color.clear
            .overlay {
                CharacterCanvas(drawing: frame.drawing, placements: frame.placements, crop: Self.reach)
                    .frame(width: Self.reach.width * scale, height: Self.reach.height * scale)
                    .offset(y: (Self.reach.midY - Self.canvas.height / 2) * scale)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                if hasNote, let corner = phoneCorner(frame.placements) {
                    phone(lines: buzzes ? PhoneBuzz.lines(at: seconds) : 0)
                        .position(x: corner.x * scale, y: corner.y * scale)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.wildcard(Motion.celebrate, reduceMotion: reduceMotion), value: hasNote)
            .rotationEffect(.degrees(buzzes ? PhoneBuzz.sway(at: seconds) : 0), anchor: .bottom)
            .offset(y: -lift * unit - (buzzes ? PhoneBuzz.hop(at: seconds) * scale : 0))
            .frame(width: Self.canvas.width * scale, height: Self.canvas.height * scale)
            .contentShape(Rectangle())
            .position(
                x: coach.spot.x * unit,
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

    /// The unread dot on the phone, with two buzz lines beside it showing by `lines`.
    private func phone(lines: Double) -> some View {
        Circle()
            .fill(Color(role: .bgBrand, in: .gym))
            .frame(width: Self.dot, height: Self.dot)
            .padding(Self.dotRing)
            .background(Circle().fill(Color(role: .bgCanvas, in: .gym)))
            .overlay(alignment: .topTrailing) {
                ZStack(alignment: .topLeading) {
                    Capsule().frame(width: Self.buzzLine.width, height: Self.buzzLine.height)
                        .rotationEffect(.degrees(-30))
                    Capsule().frame(width: Self.buzzLine.width, height: Self.buzzLine.height * 0.8)
                        .offset(x: Self.buzzLine.height / 2, y: Self.buzzLine.height + 1)
                }
                .foregroundStyle(Color(role: .fgDefault, in: .gym))
                .opacity(lines)
                .offset(x: Self.buzzLine.height + 2, y: -Self.buzzLine.height / 2)
            }
            .accessibilityHidden(true)
    }
}

/// The coach on the sideline as a button by its name, for VoiceOver and UI tests, saying whether a
/// note waits; it tells where it stands on screen, for its note to open from.
struct SidelineCoachButton: ViewModifier {
    let name: String
    let hasNote: Bool
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
            .accessibilityValue(hasNote ? Text("有新消息", bundle: .module) : Text(verbatim: ""))
            .accessibilityIdentifier("today.coach")
            .accessibilityAddTraits(.isButton)
    }
}
#endif
