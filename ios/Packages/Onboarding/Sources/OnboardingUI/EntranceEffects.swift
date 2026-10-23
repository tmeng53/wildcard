#if os(iOS)
import CheckInDomain
import DesignSystem
import DesignSystemUI
import OnboardingDomain
import SwiftUI

/// What happens on the floor around the spot, from the clock: the dashed spot breathing while
/// it waits, the dust, the shockwave and the ring closing on landing.
private struct SpotEffects: View {
    let time: Double
    let puffs: [EntranceMotion.Puff]
    let unit: Double
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        Canvas { context, _ in
            let spot = CGPoint(x: StageLayout.mySpot.x * unit, y: StageLayout.mySpot.y * unit)
            // Home's ground ring, around my feet.
            let ring = CGSize(width: 210 * StageLayout.myScale * unit, height: 71.4 * StageLayout.myScale * unit)
            func ellipse(_ size: CGSize) -> Path {
                Path(
                    ellipseIn: CGRect(
                        x: spot.x - size.width / 2, y: spot.y - size.height / 2, width: size.width,
                        height: size.height))
            }
            let mark = EntranceMotion.spotMark(at: time)
            if mark.opacity > 0 {
                let size = CGSize(width: ring.width * mark.scale, height: ring.height * mark.scale)
                context.stroke(
                    ellipse(size), with: .color(Color(role: .fgOnScene, in: theme).opacity(mark.opacity)),
                    style: StrokeStyle(lineWidth: 1.6 * unit, dash: [4 * unit, 3 * unit]))
            }
            if let wave = EntranceMotion.shockwave(at: time) {
                let size = CGSize(
                    width: wave.radius * 2 * unit, height: wave.radius * 2 * EntranceMotion.shockwaveFlattening * unit)
                context.stroke(
                    ellipse(size), with: .color(Color(role: .fgOnScene, in: theme).opacity(wave.opacity)),
                    lineWidth: wave.line * unit)
            }
            let closing = EntranceMotion.ring(at: time)
            if closing.opacity > 0 {
                context.stroke(
                    ellipse(ring).trimmedPath(from: 0, to: closing.drawn),
                    with: .color(Color(role: .ring, in: theme).opacity(closing.opacity)),
                    style: StrokeStyle(lineWidth: 3 * unit, lineCap: .round))
            }
            for puff in puffs {
                guard let state = puff.state(at: time) else { continue }
                let radius = state.radius * unit
                context.fill(
                    Path(
                        ellipseIn: CGRect(
                            x: state.center.x * unit - radius, y: state.center.y * unit - radius, width: radius * 2,
                            height: radius * 2)),
                    with: .color(Color(role: .bgCanvas, in: theme).opacity(state.opacity)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Paper bits thrown up from the spot on landing, in the accent, ink and white, falling back
/// under gravity and spinning as they go.
private struct Confetti: View {
    let start: Date?
    let origin: CGPoint
    let unit: Double
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Bit {
        let angle: Double
        let speed: Double
        let spin: Double
        let flip: Double
        let life: Double
        let role: ColorRole
    }

    /// The same throw every time, like the design's.
    private static let bits: [Bit] = {
        var seed: UInt64 = 11
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(UInt64(1) << 53)
        }
        let roles: [ColorRole] = [.bgAccent, .fgDefault, .bgCanvas]
        return (0..<18).map { index in
            Bit(
                angle: -Double.pi / 2 + (next() - 0.5) * 2.3, speed: 330 + next() * 260, spin: (next() - 0.5) * 1400,
                flip: 8 + next() * 10, life: 1.1 + next() * 0.5, role: roles[index % roles.count])
        }
    }()
    private static let gravity = 900.0
    private static let bitSize = CGSize(width: 7, height: 12)

    var body: some View {
        if let start, !reduceMotion {
            TimelineView(.animation) { timeline in
                Canvas { context, _ in
                    let elapsed = timeline.date.timeIntervalSince(start)
                    for bit in Self.bits where elapsed < bit.life {
                        let left = origin.x + cos(bit.angle) * bit.speed * elapsed * unit
                        let y =
                            origin.y + (sin(bit.angle) * bit.speed * elapsed + Self.gravity * elapsed * elapsed / 2)
                            * unit
                        var piece = context
                        piece.opacity = max(0, 1 - max(0, elapsed - bit.life * 0.6) / (bit.life * 0.4))
                        piece.translateBy(x: left, y: y)
                        piece.rotate(by: .degrees(bit.spin * elapsed))
                        piece.scaleBy(x: cos(elapsed * bit.flip), y: 1)
                        let rect = CGRect(
                            x: -Self.bitSize.width / 2, y: -Self.bitSize.height / 2, width: Self.bitSize.width,
                            height: Self.bitSize.height)
                        piece.fill(
                            Path(rect), with: .color(Color(role: bit.role, in: theme)))
                    }
                }
            }
        }
    }
}

#endif
