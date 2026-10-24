#if canImport(SwiftUI)
import DesignSystem
import Foundation
import SwiftUI

/// Where the character stands while it is dressed (sign-up, and 我): a graphite ticket with a
/// small lamp at the top, two flat beams and a pool of light at its feet, the W mark and the
/// day the member signed up along the top, and a stub under the tear line for its name. It wears
/// the brand, never the scene, so the editor gives no scene away. The content fills the ticket,
/// standing with its feet on the light; the stub holds the name.
public struct CharacterStage<Content: View, Stub: View>: View {
    @Environment(\.sceneTheme) private var theme
    private let issued: Date?
    private let content: Content
    private let stub: Stub

    /// The stub's height under the tear line (44 of the design's 300).
    public static var stubHeight: Double { TicketArt.stub }

    /// `issued` is the day printed in the top corner: the day the member signed up. Nil prints none.
    public init(issued: Date?, @ViewBuilder content: () -> Content, @ViewBuilder stub: () -> Stub) {
        self.issued = issued
        self.content = content()
        self.stub = stub()
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            TicketArt()
            content
            stub
                .frame(maxWidth: .infinity)
                .frame(height: Self.stubHeight)
        }
        .overlay(alignment: .topTrailing) {
            if let issued {
                Text(verbatim: TicketArt.stamp(issued))
                    .typeStyle(TypeRamp.ticketDate)
                    .foregroundStyle(Color(role: .fgBrandStamp, in: theme))
                    // A picture of a ticket: the date keeps its size and sits on the design's baseline.
                    .dynamicTypeSize(.large)
                    .alignmentGuide(.top) { $0[.firstTextBaseline] - TicketArt.dateBaseline }
                    .padding(.trailing, TicketArt.edge)
            }
        }
        .clipShape(TicketShape(notchFromBottom: Self.stubHeight))
    }
}

/// A ticket: rounded corners and a half-round notch in each side at the tear line.
struct TicketShape: Shape {
    /// How far above the bottom the notches' centers are.
    let notchFromBottom: Double
    private let notch: Double = 11

    func path(in rect: CGRect) -> Path {
        let ticket = Path(roundedRect: rect, cornerRadius: Radius.ticket, style: .continuous)
        let y = rect.maxY - notchFromBottom
        var notches = Path()
        for side in [rect.minX, rect.maxX] {
            notches.addEllipse(in: CGRect(x: side - notch, y: y - notch, width: notch * 2, height: notch * 2))
        }
        return ticket.subtracting(notches)
    }
}

/// The ticket's face, drawn as the design draws it on a 358 by 300 stage: the lamp, beams and
/// light keep to the middle and the marks to the edges, so it reads the same on any width. Flat
/// white at low opacities, no gradients or blur.
struct TicketArt: View {
    @Environment(\.sceneTheme) private var theme

    static let stub: Double = 44
    /// The W mark's and the date's distance from the side edges.
    static let edge: Double = 20
    /// The date's baseline, from the top.
    static let dateBaseline: Double = 32

    /// 2026.10.23, in the phone's calendar.
    static func stamp(_ day: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d.%02d.%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    var body: some View {
        Canvas { context, size in
            let middle = size.width / 2
            let tear = size.height - Self.stub
            let light = Color(role: .fgOnBrand, in: theme)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(role: .bgBrand, in: theme)))

            // Two beams from the lamp to the floor, the narrow one over the wide one.
            func beam(top: Double, bottom: Double) -> Path {
                Path { path in
                    path.move(to: CGPoint(x: middle - top, y: 9))
                    path.addLine(to: CGPoint(x: middle + top, y: 9))
                    path.addLine(to: CGPoint(x: middle + bottom, y: tear - 4))
                    path.addLine(to: CGPoint(x: middle - bottom, y: tear - 4))
                    path.closeSubpath()
                }
            }
            context.fill(beam(top: 13, bottom: 97), with: .color(light.opacity(0.07)))
            context.fill(beam(top: 7, bottom: 61), with: .color(light.opacity(0.06)))

            // The pool of light the character stands in.
            func pool(width: Double, height: Double) -> Path {
                Path(ellipseIn: CGRect(x: middle - width, y: tear - 6 - height, width: width * 2, height: height * 2))
            }
            context.fill(pool(width: 98, height: 15), with: .color(light.opacity(0.14)))
            context.fill(pool(width: 60, height: 9), with: .color(light.opacity(0.1)))

            // The lamp, hanging from the top edge, and its lit lens.
            context.fill(
                Path(
                    roundedRect: CGRect(x: middle - 16, y: -6, width: 32, height: 14),
                    cornerSize: CGSize(width: 5, height: 5)),
                with: .color(Color(role: .bgBrandLamp, in: theme)))
            context.fill(
                Path(
                    roundedRect: CGRect(x: middle - 12, y: 6, width: 24, height: 3),
                    cornerSize: CGSize(width: 1.5, height: 1.5)),
                with: .color(light.opacity(0.9)))

            // The stub, and the dashed tear line along its top.
            context.fill(
                Path(CGRect(x: 0, y: tear, width: size.width, height: Self.stub)),
                with: .color(Color(role: .bgBrandStub, in: theme)))
            var tearLine = Path()
            tearLine.move(to: CGPoint(x: 22, y: tear))
            tearLine.addLine(to: CGPoint(x: size.width - 22, y: tear))
            context.stroke(
                tearLine, with: .color(light.opacity(0.28)), style: StrokeStyle(lineWidth: 2, dash: [4, 5]))

            // The W mark in the top corner.
            var mark = Path()
            let strokes: [(Double, Double)] = [(0, 0), (5, 22), (10, 0), (15, 22), (20, 0)]
            for (index, point) in strokes.enumerated() {
                let corner = CGPoint(x: Self.edge + point.0 * 0.8, y: 18 + point.1 * 0.8)
                if index == 0 { mark.move(to: corner) } else { mark.addLine(to: corner) }
            }
            context.stroke(
                mark, with: .color(light.opacity(0.85)),
                style: StrokeStyle(lineWidth: 3.68, lineJoin: .miter, miterLimit: 4))
        }
        .accessibilityHidden(true)
    }
}
#endif
