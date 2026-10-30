#if os(iOS)
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The scene drawn faintly behind the poster: white lines (the pool's ripples, the track's lanes
/// running off at an angle, the court's lines, the gym's floor grid, the climbing wall's panels
/// with one route of holds), and over them a few of the scene's own things (`PosterProps`). Drawn at the poster's
/// own size.
struct PosterArt: View {
    let theme: SceneTheme

    private let lineOpacity = 0.10
    private let lineWidth: Double = 2
    private let holdOpacity = 0.13
    private let propOpacity = 0.2

    var body: some View {
        Canvas { context, size in
            let ink = Color(role: .bgCanvas, in: theme)
            context.stroke(
                lines(in: size), with: .color(ink.opacity(lineOpacity)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            if theme == .climbing {
                context.fill(holds, with: .color(ink.opacity(holdOpacity)), style: FillStyle(eoFill: true))
            }
            PosterProps.draw(PosterProps.props(for: theme), in: context, color: ink, opacity: propOpacity)
        }
        .accessibilityHidden(true)
    }

    private func lines(in size: CGSize) -> Path {
        switch theme {
        case .pool: ripples(in: size)
        case .track: trackLanes(in: size)
        case .tennis: court(in: size)
        case .gym: floorGrid(in: size)
        case .climbing: panels(in: size)
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

    /// The climbing wall's plywood panels: three across, four down.
    private func panels(in size: CGSize) -> Path {
        var path = Path()
        for column in stride(from: 120.0, to: size.width, by: 120) {
            path.move(to: CGPoint(x: column, y: 0))
            path.addLine(to: CGPoint(x: column, y: size.height))
        }
        for row in stride(from: 120.0, to: size.height, by: 120) {
            path.move(to: CGPoint(x: 0, y: row))
            path.addLine(to: CGPoint(x: size.width, y: row))
        }
        return path
    }

    /// One route of six holds zigzagging up the wall's left side (the props sit on the right):
    /// each one of three shapes, turned a set amount, with its bolt hole cut out.
    private var holds: Path {
        let shapes: [[Double]] = [
            [1, 0.82, 1.05, 0.9, 1, 0.78], [1.1, 0.9, 0.75, 1.05, 0.85, 0.95], [0.9, 1.05, 0.95, 0.8, 1.1, 0.9],
        ]
        let route: [(center: CGPoint, size: Double, degrees: Double)] = [
            (CGPoint(x: 52, y: 398), 18, 0), (CGPoint(x: 108, y: 322), 14, 50), (CGPoint(x: 60, y: 250), 16, 110),
            (CGPoint(x: 138, y: 186), 13, 160), (CGPoint(x: 86, y: 112), 17, 220), (CGPoint(x: 160, y: 44), 14, 290),
        ]
        let bolt = 3.0
        var path = Path()
        for (index, hold) in route.enumerated() {
            let turn = hold.degrees * .pi / 180
            let corners = shapes[index % shapes.count].enumerated().map { corner, reach in
                let angle = Double(corner) / 6 * 2 * .pi
                let across = cos(angle) * hold.size * reach
                let down = sin(angle) * hold.size * reach * 0.8
                return CGPoint(
                    x: hold.center.x + across * cos(turn) - down * sin(turn),
                    y: hold.center.y + across * sin(turn) + down * cos(turn))
            }
            path.addPath(blob(through: corners))
            path.addEllipse(
                in: CGRect(x: hold.center.x - bolt, y: hold.center.y - bolt, width: bolt * 2, height: bolt * 2))
        }
        return path
    }

    /// A smooth closed shape through the midpoints of its corners, the corners as controls.
    private func blob(through points: [CGPoint]) -> Path {
        func middle(_ first: CGPoint, _ second: CGPoint) -> CGPoint {
            CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
        }
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: middle(last, first))
        for (index, point) in points.enumerated() {
            path.addQuadCurve(to: middle(point, points[(index + 1) % points.count]), control: point)
        }
        path.closeSubpath()
        return path
    }
}
#endif
