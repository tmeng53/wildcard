#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

// swiftlint:disable identifier_name - x and y are the names CGPoint and CGRect use.

/// A scene to pick for the squad's next week, as a tile with its name under it (the 战报's
/// last page and squad settings, approved 2026-10-22). A scene the squad has trained at is a
/// card in the scene's colour with its pattern and icon; one it never has is a kraft carton,
/// the whole tile, with nothing to say what is inside. Picked, the tile lifts and tilts in an
/// ink ring, and a carton shakes at once and again every 2.4 s. There is never a preview of
/// the scene itself.
public struct SceneTile: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pickedAt: Date?
    private let scene: SceneTheme
    private let name: Text
    private let isOpened: Bool
    private let isSelected: Bool
    private let height: Double
    private let action: () -> Void

    /// `height` is the face's: 68 on the 战报's sticker, 64 in squad settings.
    public init(
        scene: SceneTheme, name: Text, isOpened: Bool, isSelected: Bool, height: Double = 68,
        action: @escaping () -> Void
    ) {
        self.scene = scene
        self.name = name
        self.isOpened = isOpened
        self.isSelected = isSelected
        self.height = height
        self.action = action
    }

    /// The prototype's selection spring: cubic-bezier(0.3, 1.4, 0.5, 1) over 0.2 s.
    private static let lift = Animation.timingCurve(0.3, 1.4, 0.5, 1, duration: 0.2)
    /// Between the face and its name.
    private static let nameGap = 6.0
    /// The lines of the name, 12 on 16.
    private static let nameHeight = 16.0

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.pick, style: .continuous)
        Button(action: action) {
            VStack(spacing: Self.nameGap) {
                face
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipShape(shape)
                    .background {
                        // Two rings outside the face, as CSS's two box-shadow spreads draw them.
                        if isSelected {
                            RoundedRectangle(cornerRadius: Radius.pick + 4, style: .continuous)
                                .fill(Color(Palette.ink)).padding(-4)
                            RoundedRectangle(cornerRadius: Radius.pick + 2, style: .continuous)
                                .fill(Color(Palette.white)).padding(-2)
                        }
                    }
                    .scaleEffect(isSelected && !reduceMotion ? 1.06 : 1)
                    .rotationEffect(.degrees(isSelected && !reduceMotion ? -4 : 0))
                    .offset(y: isSelected && !reduceMotion ? -4 : 0)
                name
                    .typeStyle(isSelected ? TypeRamp.tabSelected : TypeRamp.caption)
                    .foregroundStyle(Color(isSelected ? Palette.ink : Palette.inkSecondary))
                    .lineLimit(1)
                    .frame(height: Self.nameHeight)
            }
        }
        .buttonStyle(.plain)
        .animation(Self.lift, value: isSelected)
        .onChange(of: isSelected, initial: true) { _, selected in pickedAt = selected ? .now : nil }
        .haptic(.pick, trigger: isSelected) { _, new in new }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private var face: some View {
        if isOpened {
            ScenePattern(scene: scene)
        } else if let pickedAt, !reduceMotion {
            TimelineView(.animation) { timeline in
                CartonFace()
                    .rotationEffect(
                        .degrees(Wiggle.degrees(at: timeline.date.timeIntervalSince(pickedAt))), anchor: .bottom)
            }
            .background(Color(Palette.kraft))
        } else {
            CartonFace()
        }
    }
}

/// A scene the squad knows: its colour, its pattern in white (volt on the gym's graphite) and
/// its icon in the middle.
struct ScenePattern: View {
    let scene: SceneTheme

    var body: some View {
        let ink = scene == .gym ? Palette.volt : Palette.white
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(Self.base(of: scene))))
            Self.drawPattern(of: scene, in: &context, size: size, ink: Color(ink))
            let icon = Self.icon(of: scene).applying(
                CGAffineTransform(translationX: (size.width - 24) / 2, y: (size.height - 24) / 2))
            context.stroke(
                icon, with: .color(Color(ink)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        }
    }

    /// The card's colour: the scene's signature, the gym's graphite.
    static func base(of scene: SceneTheme) -> SRGBColor {
        switch scene {
        case .track: Palette.trackSignature
        case .pool: Palette.poolSignature
        case .gym: Palette.graphite
        case .tennis: Palette.tennisSignature
        case .climbing: Palette.climbingSignature
        }
    }

    /// The prototype's CSS patterns, drawn: lane lines, a dot grid, diagonal volt stripes, the
    /// court's centre lines and a few climbing holds.
    static func drawPattern(of scene: SceneTheme, in context: inout GraphicsContext, size: CGSize, ink: Color) {
        switch scene {
        case .track:
            var lines = Path()
            for top in stride(from: 11.0, to: size.height, by: 12.5) {
                lines.addRect(CGRect(x: 0, y: top, width: size.width, height: 1.5))
            }
            context.fill(lines, with: .color(ink.opacity(0.4)))
        case .pool:
            var dots = Path()
            for top in stride(from: 0.0, to: size.height, by: 9) {
                for left in stride(from: 0.0, to: size.width, by: 9) {
                    dots.addEllipse(in: CGRect(x: left + 4.5 - 1.7, y: top + 4.5 - 1.7, width: 3.4, height: 3.4))
                }
            }
            context.fill(dots, with: .color(ink.opacity(0.3)))
        case .gym:
            // 135° stripes every 10 points, 2 wide along the gradient: lines where x + y is constant.
            var stripes = Path()
            let step = 10 * 2.0.squareRoot()
            let band = 2 * 2.0.squareRoot()
            for start in stride(from: 8 * 2.0.squareRoot(), to: size.width + size.height, by: step) {
                stripes.move(to: CGPoint(x: start, y: 0))
                stripes.addLine(to: CGPoint(x: start + band, y: 0))
                stripes.addLine(to: CGPoint(x: start + band - size.height, y: size.height))
                stripes.addLine(to: CGPoint(x: start - size.height, y: size.height))
                stripes.closeSubpath()
            }
            context.fill(stripes, with: .color(ink.opacity(0.16)))
        case .tennis:
            var lines = Path()
            lines.addRect(CGRect(x: size.width / 2 - 0.75, y: 0, width: 1.5, height: size.height))
            lines.addRect(CGRect(x: 0, y: size.height / 2 - 0.75, width: size.width, height: 1.5))
            context.fill(lines, with: .color(ink.opacity(0.45)))
        case .climbing:
            var holds = Path()
            for (x, y, radius) in [(0.18, 0.24, 3.0), (0.76, 0.18, 2.5), (0.34, 0.8, 3.0), (0.84, 0.7, 2.0)] {
                holds.addEllipse(
                    in: CGRect(
                        x: x * size.width - radius, y: y * size.height - radius, width: radius * 2, height: radius * 2))
            }
            context.fill(holds, with: .color(ink.opacity(0.28)))
        }
    }

    /// The scene's 24-point line icon: lanes, waves, a dumbbell, a ball, a peak.
    static func icon(of scene: SceneTheme) -> Path {
        var path = Path()
        switch scene {
        case .track:
            path.addRoundedRect(in: CGRect(x: 1, y: 6, width: 22, height: 12), cornerSize: CGSize(width: 6, height: 6))
            path.addRoundedRect(in: CGRect(x: 5, y: 10, width: 14, height: 4), cornerSize: CGSize(width: 2, height: 2))
        case .pool:
            for top in [9.0, 15.0] {
                path.move(to: CGPoint(x: 2, y: top))
                path.addCurve(
                    to: CGPoint(x: 9, y: top), control1: CGPoint(x: 4.5, y: top - 2),
                    control2: CGPoint(x: 6.5, y: top - 2))
                path.addCurve(
                    to: CGPoint(x: 16, y: top), control1: CGPoint(x: 11.5, y: top + 2),
                    control2: CGPoint(x: 13.5, y: top + 2))
                path.addCurve(
                    to: CGPoint(x: 22, y: top), control1: CGPoint(x: 18.5, y: top - 2),
                    control2: CGPoint(x: 20.5, y: top - 2))
            }
        case .gym:
            for (x, top, bottom) in [(6.0, 7.0, 17.0), (3, 9.5, 14.5), (18, 7, 17), (21, 9.5, 14.5)] {
                path.move(to: CGPoint(x: x, y: top))
                path.addLine(to: CGPoint(x: x, y: bottom))
            }
            path.move(to: CGPoint(x: 6, y: 12))
            path.addLine(to: CGPoint(x: 18, y: 12))
        case .tennis:
            path.addEllipse(in: CGRect(x: 3, y: 3, width: 18, height: 18))
            path.move(to: CGPoint(x: 5.6, y: 5.6))
            path.addCurve(
                to: CGPoint(x: 5.6, y: 18.4), control1: CGPoint(x: 8.6, y: 8.6), control2: CGPoint(x: 8.6, y: 15.4))
            path.move(to: CGPoint(x: 18.4, y: 5.6))
            path.addCurve(
                to: CGPoint(x: 18.4, y: 18.4), control1: CGPoint(x: 15.4, y: 8.6), control2: CGPoint(x: 15.4, y: 15.4))
        case .climbing:
            path.move(to: CGPoint(x: 3, y: 20))
            path.addLine(to: CGPoint(x: 9, y: 9))
            path.addLine(to: CGPoint(x: 13, y: 15))
            path.addLine(to: CGPoint(x: 15, y: 12))
            path.addLine(to: CGPoint(x: 21, y: 20))
            path.closeSubpath()
        }
        return path
    }
}

/// The carton as a tile: kraft, the closed flaps' band along the top with its edge, packing
/// tape down the middle and two "this way up" arrows.
struct CartonFace: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(Palette.kraft)))
            context.fill(
                Path(CGRect(x: 0, y: 0, width: size.width, height: 16)), with: .color(Color(Palette.kraftFlap)))
            context.fill(
                Path(CGRect(x: 0, y: 16, width: size.width, height: 2)), with: .color(Color(Palette.kraftBandLine)))
            context.fill(
                Path(CGRect(x: size.width / 2 - 6, y: 0, width: 12, height: size.height * 0.58)),
                with: .color(Color(Palette.kraftTape)))
            // The arrows' 22 × 12 box sits 6 from the left and 7 from the bottom.
            var arrows = Path()
            for x in [5.0, 15.0] {
                arrows.move(to: CGPoint(x: x, y: 11))
                arrows.addLine(to: CGPoint(x: x, y: 2))
                arrows.move(to: CGPoint(x: x - 3.5, y: 5.5))
                arrows.addLine(to: CGPoint(x: x, y: 2))
                arrows.addLine(to: CGPoint(x: x + 3.5, y: 5.5))
            }
            context.stroke(
                arrows.applying(CGAffineTransform(translationX: 6, y: size.height - 7 - 12)),
                with: .color(Color(Palette.kraftInk)),
                style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
    }
}
// swiftlint:enable identifier_name
#endif
