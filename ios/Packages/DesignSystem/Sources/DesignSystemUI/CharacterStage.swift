#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// The scene's floor markings in white: track lanes, pool lane ropes, a tennis court's lines, a
/// gym's floor grid, climbing holds. Drawn in `band`, the floor's rectangle; climbing's holds go
/// on the wall above it.
struct ScenePattern: View {
    @Environment(\.sceneTheme) private var theme
    /// The floor's top, as a fraction of the height.
    let floorTop: Double
    let ink: Color

    /// The design draws each pattern on a 358 by 96 point floor.
    private static let designWidth: Double = 358
    private static let designFloor: Double = 96

    var body: some View {
        Canvas { context, size in
            let top = size.height * floorTop
            let unitX = size.width / Self.designWidth
            let unitY = (size.height - top) / Self.designFloor
            func across(_ y: Double, from start: Double = 0) -> Path {
                Path { path in
                    path.move(to: CGPoint(x: start * unitX, y: top + y * unitY))
                    path.addLine(to: CGPoint(x: size.width, y: top + y * unitY))
                }
            }
            func down(_ column: Double, from y: Double = 0) -> Path {
                Path { path in
                    path.move(to: CGPoint(x: column * unitX, y: top + y * unitY))
                    path.addLine(to: CGPoint(x: column * unitX, y: size.height))
                }
            }
            let line = StrokeStyle(lineWidth: 2)
            switch theme {
            case .track:
                for y in [24.0, 52, 80] { context.stroke(across(y), with: .color(ink), style: line) }
            case .pool:
                let rope = StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 9])
                for y in [22.0, 58] { context.stroke(across(y, from: 6), with: .color(ink), style: rope) }
            case .tennis:
                context.stroke(across(26), with: .color(ink), style: line)
                context.stroke(down(Self.designWidth / 2, from: 26), with: .color(ink), style: line)
            case .gym:
                for column in [60.0, 150, 240, 330] { context.stroke(down(column), with: .color(ink), style: line) }
                context.stroke(across(48), with: .color(ink), style: line)
            case .climbing:
                // Holds on the wall, placed on the design's 358 by 300 stage.
                let holds: [(x: Double, y: Double, r: Double)] = [
                    (46, 58, 7), (88, 128, 5), (300, 74, 8), (318, 150, 5), (270, 30, 5), (34, 168, 6),
                ]
                let unitWall = size.height / 300
                for hold in holds {
                    let rect = CGRect(
                        x: hold.x * unitX - hold.r, y: hold.y * unitWall - hold.r, width: hold.r * 2,
                        height: hold.r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(Color(role: .borderDefault, in: theme)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The scene's floor full screen, in the scene's color with its markings: where sign-up's crowd
/// and 上场 stand.
public struct SceneFloor: View {
    @Environment(\.sceneTheme) private var theme

    public init() {}

    public var body: some View {
        ZStack {
            Color(role: .bgScene, in: theme)
            ScenePattern(floorTop: 0.55, ink: Color(role: .bgCanvas, in: theme).opacity(theme == .gym ? 0.12 : 0.7))
        }
        .accessibilityHidden(true)
    }
}

/// Where the character stands while it is being dressed or shown off: a subtle block with
/// 12-point corners and a grey floor band carrying the scene's markings, so the scene shows
/// without its color competing with the accent. The content stands with its feet on the floor.
public struct CharacterStage<Content: View>: View {
    @Environment(\.sceneTheme) private var theme
    private let content: Content

    /// The floor band's top, as a fraction of the stage's height (204 of 300 in the design).
    public static var floorTop: Double { 0.68 }

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color(role: .bgSubtle, in: theme)
                Color(role: .borderDefault, in: theme)
                    .frame(height: proxy.size.height * (1 - Self.floorTop))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                ScenePattern(floorTop: Self.floorTop, ink: Color(role: .bgCanvas, in: theme))
                content
            }
        }
        .clipShape(shape)
    }
}
#endif
