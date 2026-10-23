import DesignSystem
import Foundation

/// The reveal after 「就它了」, frame by frame: the page dims, a kraft carton drops, squashes,
/// shakes the screen, rattles and hops, its flaps fly off in a ring of the scene's colour and
/// confetti, and the scene's card rises and fills the screen. A scene the squad has trained
/// at before skips the carton and rises at once. No text anywhere.
///
/// Every number is the approved prototype's (Tracy, 2026-10-22: 「要 pixel perfect」), in the
/// design's 390 × 844 points with y down, and `frame(at:)` is a pure function of the time, so
/// tests pin it to the prototype and the screen only draws what it returns. Once the card
/// covers the screen (`covered`), the home takes over under the last of the confetti and its
/// squad drops in.
public struct Unboxing: Hashable, Sendable {
    /// Whether the scene comes in a carton: a scene the squad has never trained at.
    public let boxed: Bool

    public init(boxed: Bool) {
        self.boxed = boxed
    }

    /// The design's stage.
    public static let stage = Size(width: 390, height: 844)

    /// When the card has filled the screen, on this reveal's clock.
    public var covered: Double { Self.cardFull - lead }
    /// When the last confetti has faded, and the reveal is over.
    public var finished: Double { boxed ? Self.burst + Self.confettiLife : covered }

    /// How much earlier everything after the carton happens for a scene with no carton.
    private var lead: Double { boxed ? 0 : 1.75 }

    // The prototype's moments, in seconds from 「就它了」.
    static let land = 0.6
    static let burst = 1.66
    static let cardRise = 1.75
    static let cardFull = 2.8
    static let confettiLife = 1.3

    /// Everything on screen `time` seconds after 「就它了」.
    public func frame(at time: Double) -> UnboxFrame {
        UnboxFrame(
            dim: 0.86 * Tween.cubicOut(Tween.progress(time, from: 0, lasting: 0.25)),
            shake: shake(at: time),
            carton: boxed ? carton(at: time) : nil,
            dust: boxed ? Self.puffs(at: time, landingAt: Self.land, on: Point(x: 195, y: 520), count: 6) : [],
            ring: boxed ? ring(at: time) : nil,
            confetti: boxed ? confetti(at: time) : [],
            card: card(at: time + lead))
    }

    /// The whole screen jolts as the carton lands.
    private func shake(at time: Double) -> Point {
        let jolt = boxed ? Tween.progress(time, from: Self.land, lasting: 0.18) : 1
        guard jolt > 0, jolt < 1 else { return Point(x: 0, y: 0) }
        return Point(x: sin(jolt * 40) * 5 * (1 - jolt), y: cos(jolt * 33) * 4 * (1 - jolt))
    }

    private func carton(at time: Double) -> CartonPose? {
        guard time <= 2.6 else { return nil }
        func progress(_ start: Double, _ duration: Double) -> Double {
            Tween.progress(time, from: start, lasting: duration)
        }
        var lift = Tween.mix(-560, 0, Tween.quadIn(progress(0.1, 0.5)))
        var (scaleX, scaleY, rotation) = (1.0, 1.0, 0.0)
        if time >= Self.land {
            let wobble = Tween.squash(progress(Self.land, 0.6))
            scaleY = 1 - 0.16 * wobble
            scaleX = 1 + 0.12 * wobble
        }
        let rattle = progress(0.95, 0.7)
        if rattle > 0, rattle < 1 { rotation = sin(rattle * 38) * (2 + 7 * rattle) }
        func hop(_ start: Double, _ height: Double) -> Double {
            let step = progress(start, 0.24)
            return step > 0 && step < 1 ? -height * sin(step * .pi) : 0
        }
        lift += hop(1.08, 14) + hop(1.36, 24)
        let crouch = progress(1.52, 0.13)
        if crouch > 0, crouch < 1 {
            scaleY *= 1 - 0.1 * sin(crouch * .pi)
            scaleX *= 1 + 0.08 * sin(crouch * .pi)
        }
        let sink = Tween.quadIn(progress(1.95, 0.4))
        lift += 200 * sink
        let open = Tween.cubicOut(progress(1.65, 0.38))
        return CartonPose(
            offsetY: lift, rotation: rotation, scaleX: scaleX, scaleY: scaleY, opacity: 1 - sink,
            leftFlap: FlapPose(x: -40 * open, y: -150 * open, rotation: -130 * open),
            rightFlap: FlapPose(x: 44 * open, y: -170 * open, rotation: 140 * open),
            flapOpacity: 1 - progress(1.85, 0.2))
    }

    private func ring(at time: Double) -> RingPose? {
        let grow = Tween.progress(time, from: Self.burst, lasting: 0.5)
        guard grow > 0, grow < 1 else { return nil }
        return RingPose(
            center: Point(x: 195, y: 360), diameter: Tween.mix(40, 420, Tween.cubicOut(grow)),
            lineWidth: Tween.mix(10, 2, grow), opacity: 1 - grow)
    }

    private func confetti(at time: Double) -> [ConfettiPiece] {
        let flight = time - Self.burst
        guard flight >= 0, flight <= Self.confettiLife else { return [] }
        return (0..<34).map { index in
            let angle = -Double.pi * (0.06 + 0.88 * Double((index * 7) % 34) / 33)
            let speed = 260 + Double(index % 4) * 70
            let square = index % 3 == 0
            return ConfettiPiece(
                index: index,
                origin: Point(
                    x: 195 + cos(angle) * speed * flight,
                    y: 365 + sin(angle) * speed * flight + 520 * flight * flight),
                size: square ? Size(width: 8, height: 8) : Size(width: 14, height: 6),
                cornerRadius: square ? 4 : 1.5,
                color: ConfettiColor.cycle[index % ConfettiColor.cycle.count],
                rotation: Double((index * 97) % 360) + (index % 2 == 1 ? 1 : -1) * (300 + Double(index) * 20) * flight,
                opacity: flight < 1 ? 1 : 1 - (flight - 1) / 0.3)
        }
    }

    /// `time` on the clock of a boxed reveal, where the card starts rising at 1.75 s.
    private func card(at time: Double) -> CardPose? {
        let rising = Tween.progress(time, from: Self.cardRise, lasting: 0.45)
        let rise = Tween.cubicOut(rising)
        guard rise > 0 else { return nil }
        let full = Tween.cubicInOut(Tween.progress(time, from: 2.3, lasting: 0.5))
        let (width, height) = (150.0, 220.0)
        let centerY = Tween.mix(470, 330, rise)
        let pop = Tween.mix(0.25, 1, Tween.backOut(rising))
        return CardPose(
            frame: Rect(
                x: Tween.mix(195 - width / 2, 0, full), y: Tween.mix(centerY - height / 2, 0, full),
                width: Tween.mix(width, Self.stage.width, full), height: Tween.mix(height, Self.stage.height, full)),
            cornerRadius: Tween.mix(18, 0, full),
            scale: Tween.mix(pop, 1, full),
            rotation: Tween.mix(-6 * (1 - rise) - 3, 0, full),
            border: Tween.mix(4, 0, full),
            opacity: min(1, rise * 3))
    }

    /// A puff of dust where something lands, `count` small clouds spreading out both ways.
    public static func puffs(at time: Double, landingAt start: Double, on ground: Point, count: Int) -> [DustPuff] {
        let spread = Tween.progress(time, from: start, lasting: 0.45)
        guard spread > 0, spread < 1 else { return [] }
        let eased = Tween.cubicOut(spread)
        return (0..<count).map { index in
            let side = (Double(index) / Double(count - 1) - 0.5) * 2
            return DustPuff(
                center: Point(
                    x: ground.x + side * Tween.mix(10, 48, eased), y: ground.y - Tween.mix(4, 16, eased)),
                diameter: Tween.mix(8, 22, eased), opacity: 0.9 * (1 - spread))
        }
    }
}
