#if os(iOS)
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The scene drawn faintly behind the poster, in white lines: the pool's ripples, the track's
/// lanes running off at an angle, the court's lines, the gym's floor grid, the climbing wall's
/// holds. Drawn at the poster's own size.
struct PosterArt: View {
    let theme: SceneTheme

    private let lineOpacity = 0.10
    private let lineWidth: Double = 2

    var body: some View {
        Canvas { context, size in
            context.stroke(
                path(in: size), with: .color(Color(role: .bgCanvas, in: theme).opacity(lineOpacity)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }

    private func path(in size: CGSize) -> Path {
        var path = Path()
        switch theme {
        case .pool:
            // Nine rows of ripples.
            for row in 0..<9 {
                let y = 40 + Double(row) * 56
                path.move(to: CGPoint(x: -10, y: y))
                var x = -10.0
                while x < size.width + 20 {
                    path.addQuadCurve(to: CGPoint(x: x + 18, y: y), control: CGPoint(x: x + 9, y: y - 6))
                    path.addQuadCurve(to: CGPoint(x: x + 36, y: y), control: CGPoint(x: x + 27, y: y + 6))
                    x += 36
                }
            }
        case .track:
            for lane in 0..<9 {
                path.move(to: CGPoint(x: -60 + Double(lane) * 70, y: size.height + 40))
                path.addLine(to: CGPoint(x: 180 + Double(lane) * 40, y: -10))
            }
        case .tennis:
            let left = 40.0
            let right = size.width - 40
            let top = size.height / 4
            let bottom = size.height * 3 / 4
            path.move(to: CGPoint(x: left, y: 0))
            path.addLine(to: CGPoint(x: left, y: size.height))
            path.move(to: CGPoint(x: right, y: 0))
            path.addLine(to: CGPoint(x: right, y: size.height))
            path.move(to: CGPoint(x: left, y: top))
            path.addLine(to: CGPoint(x: right, y: top))
            path.move(to: CGPoint(x: left, y: bottom))
            path.addLine(to: CGPoint(x: right, y: bottom))
            path.move(to: CGPoint(x: size.width / 2, y: top))
            path.addLine(to: CGPoint(x: size.width / 2, y: bottom))
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        case .gym:
            var x = 0.0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += 30
            }
            var y = 0.0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += 30
            }
        case .climbing:
            // Thirty holds, the same on every poster.
            var seed = 3
            func next() -> Double {
                seed = (seed * 9301 + 49297) % 233_280
                return Double(seed) / 233_280
            }
            for _ in 0..<30 {
                let center = CGPoint(x: next() * size.width, y: next() * size.height)
                let radius = 3 + next() * 5
                path.addEllipse(
                    in: CGRect(
                        x: center.x - radius, y: center.y - radius * 0.7, width: radius * 2, height: radius * 1.4))
            }
        }
        return path
    }
}
#endif
