#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// 入场券, the one card a member writes on (approved 2026-11-08): a mist ticket with a dashed
/// tear line and a half-round notch punched in each side of it. What is written goes above the
/// tear (`face`); what goes with it (photos, a style to write in) goes on the stub below, usually
/// with `TicketStamp` in its corner. 发动态, 请假条 and 意见反馈 all write on it, so never redraw it.
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
                    tear = $0 + TearStroke.halfWidth
                }
            TearStroke(over: .mist)
            stub
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.m)
                .padding(.top, Space.s)
                .padding(.bottom, Space.m)
        }
        .background(Color(role: .bgSubtle, in: theme))
        .clipShape(TicketShape(tearFromTop: tear))
    }
}

/// A post in 动态 on the same ticket (approved 2026-11-08): `TicketCard` edge to edge. The cover
/// (its photos, or the colour block) fills the top and the stub the rest, with nothing padded, and
/// the tear and the notches fall on the line between them. A stub that starts with colour (a
/// 训练's 成绩条) takes the tear in white.
public struct CoverTicket<Cover: View, Stub: View>: View {
    @Environment(\.sceneTheme) private var theme
    private let tear: TicketTear
    private let cover: Cover
    private let stub: Stub
    /// The cover's height, where the tear goes.
    @State private var coverHeight = 0.0

    public init(tear: TicketTear = .mist, @ViewBuilder cover: () -> Cover, @ViewBuilder stub: () -> Stub) {
        self.tear = tear
        self.cover = cover()
        self.stub = stub()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cover
                .onGeometryChange(for: Double.self) {
                    $0.size.height
                } action: {
                    coverHeight = $0
                }
            stub
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { TearStroke(over: tear) }
        }
        .background(Color(role: .bgSubtle, in: theme))
        .clipShape(TicketShape(tearFromTop: coverHeight))
    }
}

/// What a ticket's tear runs over: the mist stub, or colour.
public enum TicketTear: Sendable {
    case mist
    case color
}

/// The dashed tear across a ticket, clear of its notches.
private struct TearStroke: View {
    @Environment(\.sceneTheme) private var theme
    let over: TicketTear

    private static let inset: Double = 18
    private static let width: Double = 1.5
    static let halfWidth = width / 2

    var body: some View {
        TearLine()
            .stroke(ink, style: StrokeStyle(lineWidth: Self.width, dash: [4, 4]))
            .frame(height: Self.width)
            .padding(.horizontal, Self.inset)
            .accessibilityHidden(true)
    }

    private var ink: Color {
        switch over {
        case .mist: Color(role: .fgDefault, in: theme).opacity(0.18)
        case .color: Color(role: .fgOnBrand, in: theme).opacity(0.45)
        }
    }
}

/// The brand's W, in a ticket stub's corner: the same mark the character's ticket wears, in ink.
public struct TicketStamp: View {
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
