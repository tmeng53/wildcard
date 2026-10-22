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
        switch theme {
        case .pool: ripples(in: size)
        case .track: trackLanes(in: size)
        case .tennis: court(in: size)
        case .gym: floorGrid(in: size)
        case .climbing: holds(in: size)
        }
    }

    /// Nine rows of ripples.
    private func ripples(in size: CGSize) -> Path {
        var path = Path()
        for row in 0..<9 {
            let height = 40 + Double(row) * 56
            path.move(to: CGPoint(x: -10, y: height))
            var left = -10.0
            while left < size.width + 20 {
                path.addQuadCurve(
                    to: CGPoint(x: left + 18, y: height), control: CGPoint(x: left + 9, y: height - 6))
                path.addQuadCurve(
                    to: CGPoint(x: left + 36, y: height), control: CGPoint(x: left + 27, y: height + 6))
                left += 36
            }
        }
        return path
    }

    private func trackLanes(in size: CGSize) -> Path {
        var path = Path()
        for lane in 0..<9 {
            path.move(to: CGPoint(x: -60 + Double(lane) * 70, y: size.height + 40))
            path.addLine(to: CGPoint(x: 180 + Double(lane) * 40, y: -10))
        }
        return path
    }

    private func court(in size: CGSize) -> Path {
        let left = 40.0
        let right = size.width - 40
        let top = size.height / 4
        let bottom = size.height * 3 / 4
        var path = Path()
        for (start, end) in [
            (CGPoint(x: left, y: 0), CGPoint(x: left, y: size.height)),
            (CGPoint(x: right, y: 0), CGPoint(x: right, y: size.height)),
            (CGPoint(x: left, y: top), CGPoint(x: right, y: top)),
            (CGPoint(x: left, y: bottom), CGPoint(x: right, y: bottom)),
            (CGPoint(x: size.width / 2, y: top), CGPoint(x: size.width / 2, y: bottom)),
            (CGPoint(x: 0, y: size.height / 2), CGPoint(x: size.width, y: size.height / 2)),
        ] {
            path.move(to: start)
            path.addLine(to: end)
        }
        return path
    }

    private func floorGrid(in size: CGSize) -> Path {
        var path = Path()
        for column in stride(from: 0.0, through: size.width, by: 30) {
            path.move(to: CGPoint(x: column, y: 0))
            path.addLine(to: CGPoint(x: column, y: size.height))
        }
        for row in stride(from: 0.0, through: size.height, by: 30) {
            path.move(to: CGPoint(x: 0, y: row))
            path.addLine(to: CGPoint(x: size.width, y: row))
        }
        return path
    }

    /// Thirty holds, the same on every poster.
    private func holds(in size: CGSize) -> Path {
        var path = Path()
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
        return path
    }
}
#endif
