#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// 入场券, the one card a member writes on (approved 2026-11-08): a mist ticket with a dashed
/// tear line and a half-round notch punched in each side of it. What is written goes above the
/// tear (`face`); what goes with it (photos, a style to write in) goes on the stub below, usually
/// with `TicketMark` in its corner. 发动态, 请假条 and 意见反馈 all write on it, so never redraw it.
/// The tear follows the face's height, so the face may grow while typing.
public struct TicketCard<Face: View, Stub: View>: View {
    @Environment(\.sceneTheme) private var theme
    private let face: Face
    private let stub: Stub
    /// The tear line's distance from the top, as the face measures.
    @State private var tear = 0.0

    public init(@ViewBuilder face: () -> Face, @ViewBuilder stub: () -> Stub) {
        self.face = face()
        self.stub = stub()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            face
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .top], Space.m)
                .padding(.bottom, Space.s)
                .onGeometryChange(for: Double.self) {
                    $0.size.height
                } action: {
                    tear = $0 + Self.tearWidth / 2
                }
            TearLine()
                .stroke(
                    Color(role: .fgDefault, in: theme).opacity(Self.tearOpacity),
                    style: StrokeStyle(lineWidth: Self.tearWidth, dash: [4, 4])
                )
                .frame(height: Self.tearWidth)
                .padding(.horizontal, Self.tearInset)
                .accessibilityHidden(true)
            stub
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.m)
                .padding(.top, Space.s)
                .padding(.bottom, Space.m)
        }
        .background(Color(role: .bgSubtle, in: theme))
        .clipShape(TicketShape(tearFromTop: tear))
    }

    /// The tear line keeps clear of the notches.
    private static let tearInset: Double = 18
    private static let tearWidth: Double = 1.5
    private static let tearOpacity: Double = 0.18
}

/// The brand's W, in a ticket stub's corner: the same mark the character's ticket wears, in ink.
public struct TicketMark: View {
    @Environment(\.sceneTheme) private var theme

    public init() {}

    public var body: some View {
        WMark()
            .stroke(
                Color(role: .fgDefault, in: theme),
                style: StrokeStyle(lineWidth: Self.weight, lineJoin: .miter, miterLimit: 4)
            )
            .frame(width: Self.width, height: Self.height)
            .accessibilityHidden(true)
    }

    private static let width: Double = 22
    private static let height: Double = 22
    private static let weight: Double = 4
}

/// The W's four strokes, corner to corner in its frame (inset by half a stroke at the top and
/// bottom, so the points aren't cut).
struct WMark: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = 2.0
        let top = rect.minY + inset
        let bottom = rect.maxY - inset
        let xs = (0...4).map { rect.minX + rect.width * Double($0) / 4 }
        return Path { path in
            path.move(to: CGPoint(x: xs[0], y: top))
            path.addLine(to: CGPoint(x: xs[1], y: bottom))
            path.addLine(to: CGPoint(x: xs[2], y: top))
            path.addLine(to: CGPoint(x: xs[3], y: bottom))
            path.addLine(to: CGPoint(x: xs[4], y: top))
        }
    }
}

/// A straight line across the middle of its frame.
private struct TearLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}
#endif
