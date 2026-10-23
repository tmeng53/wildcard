import DesignSystem
import Foundation

// swiftlint:disable identifier_name - x and y are the names CGPoint and CGRect use.

/// One frame of `Unboxing`: what to draw, back to front, in the design's points.
public struct UnboxFrame: Hashable, Sendable {
    /// The ink over the 战报 page, 0 to 0.86.
    public let dim: Double
    /// How far the whole screen is jolted.
    public let shake: Point
    /// The carton, while there is one.
    public let carton: CartonPose?
    /// The dust where the carton lands.
    public let dust: [DustPuff]
    /// The ring of the scene's signature colour bursting out as the flaps fly.
    public let ring: RingPose?
    public let confetti: [ConfettiPiece]
    /// The scene's card, once it starts rising.
    public let card: CardPose?
}

/// The carton: 170 × 190 at (110, 330) at rest, moved about the middle of its base.
public struct CartonPose: Hashable, Sendable {
    public static let frame = Rect(x: 110, y: 330, width: 170, height: 190)

    public let offsetY: Double
    /// Degrees, clockwise.
    public let rotation: Double
    public let scaleX: Double
    public let scaleY: Double
    public let opacity: Double
    public let leftFlap: FlapPose
    public let rightFlap: FlapPose
    public let flapOpacity: Double
}

/// A flap flying off: moved, then turned about its hinge (the left flap's at (8, 48) and the
/// right's at (162, 48) in the carton's own points).
public struct FlapPose: Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let rotation: Double
}

public struct DustPuff: Hashable, Sendable {
    public let center: Point
    public let diameter: Double
    public let opacity: Double
}

/// A ring stroked inside its circle.
public struct RingPose: Hashable, Sendable {
    public let center: Point
    public let diameter: Double
    public let lineWidth: Double
    public let opacity: Double
}

public struct ConfettiPiece: Hashable, Sendable {
    public let index: Int
    /// The piece's top-left corner; it turns about its middle.
    public let origin: Point
    public let size: Size
    public let cornerRadius: Double
    public let color: ConfettiColor
    /// Degrees, clockwise.
    public let rotation: Double
    public let opacity: Double
}

/// The confetti's colours, in the order the pieces take them: the four scenes' signature
/// colours, white, kraft, and the picked scene's own.
public enum ConfettiColor: Hashable, Sendable {
    case signature(SceneTheme)
    case white
    case kraft
    case picked

    static let cycle: [ConfettiColor] = [
        .signature(.track), .signature(.pool), .signature(.tennis), .signature(.climbing), .white, .kraft, .picked,
    ]
}

/// The scene's card: its frame before scaling and turning about its middle, and a white
/// border outside it.
public struct CardPose: Hashable, Sendable {
    public let frame: Rect
    public let cornerRadius: Double
    public let scale: Double
    /// Degrees, clockwise.
    public let rotation: Double
    public let border: Double
    public let opacity: Double
}

// swiftlint:enable identifier_name
