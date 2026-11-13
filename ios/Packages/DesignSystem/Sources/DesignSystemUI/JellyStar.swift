#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// The app's one star (Tracy, 2026-11-12: every star in the app is the 软糖星): gold when lit, a
/// soft grey when not, drawn from `JellyStarShape`. Use it wherever a star shows, alone or in a
/// `StarRating`, never an SF Symbol star.
public struct JellyStar: View {
    private let lit: Bool
    private let size: CGFloat

    public init(lit: Bool = true, size: CGFloat) {
        (self.lit, self.size) = (lit, size)
    }

    public var body: some View {
        Canvas { context, canvas in
            let scale = canvas.width / JellyStarShape.side
            context.scaleBy(x: scale, y: scale)
            let star = Self.path
            let rounding = StrokeStyle(lineWidth: JellyStarShape.roundingWidth, lineJoin: .round)
            let (face, side) =
                lit
                ? (Color(Palette.starGold), Color(Palette.starGoldSide))
                : (Color(Palette.starEmpty), Color(Palette.starEmptySide))
            let under = star.offsetBy(dx: 0, dy: JellyStarShape.depth)
            context.fill(under, with: .color(side))
            context.stroke(under, with: .color(side), style: rounding)
            context.fill(star, with: .color(face))
            context.stroke(star, with: .color(face), style: rounding)
            guard lit else { return }
            let shine = JellyStarShape.shine
            var oval = context
            oval.translateBy(x: shine.x, y: shine.y)
            oval.rotate(by: .degrees(shine.degrees))
            oval.fill(
                Path(
                    ellipseIn: CGRect(
                        x: -shine.radiusX, y: -shine.radiusY, width: shine.radiusX * 2, height: shine.radiusY * 2)),
                with: .color(Color(Palette.starGoldShine)))
            let dot = JellyStarShape.sparkle
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: dot.x - dot.radius, y: dot.y - dot.radius, width: dot.radius * 2, height: dot.radius * 2)),
                with: .color(Color(Palette.starGoldShine)))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private static var path: Path {
        var path = Path()
        path.addLines(JellyStarShape.corners.map { CGPoint(x: $0.x, y: $0.y) })
        path.closeSubpath()
        return path
    }
}

/// Five `JellyStar`s, the first `rating` lit. With `onPick`, each is a button setting the rating,
/// and a star coming on pops in with a bounce (none under Reduce Motion); VoiceOver reads it as one
/// adjustable value.
public struct StarRating: View {
    private let rating: Int
    private let size: CGFloat
    private let spacing: CGFloat
    private let onPick: ((Int) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public static let count = 5
    /// How big a star grows as it comes on, before it settles.
    private static let pop = 1.18

    public init(rating: Int, size: CGFloat, spacing: CGFloat = Space.xs, onPick: ((Int) -> Void)? = nil) {
        (self.rating, self.size, self.spacing, self.onPick) = (rating, size, spacing, onPick)
    }

    public var body: some View {
        HStack(spacing: spacing) {
            ForEach(1...Self.count, id: \.self) { position in
                star(at: position)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(copy: "starRating \(rating)", bundle: .module))
        .accessibilityAdjustableAction { direction in
            guard let onPick else { return }
            switch direction {
            case .increment: onPick(min(Self.count, rating + 1))
            case .decrement: onPick(max(1, rating - 1))
            @unknown default: break
            }
        }
    }

    @ViewBuilder private func star(at position: Int) -> some View {
        let lit = position <= rating
        let face = JellyStar(lit: lit, size: size)
            .phaseAnimator([false, true], trigger: lit) { star, popping in
                star.scaleEffect(popping && lit && !reduceMotion ? Self.pop : 1)
            } animation: { _ in
                .wildcard(Motion.celebrate, reduceMotion: reduceMotion)
            }
        if let onPick {
            Button {
                onPick(position)
            } label: {
                face.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            face
        }
    }
}
#endif
