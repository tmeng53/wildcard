#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// The logo's two tickets rocking apart and back on a beat (`TicketRock`): the app's launch
/// cover and any whole-page load. On `.brand` (graphite) the front ticket is white; on `.page`
/// (the brand's light page) the colours swap, the back ticket only an outline, as on the
/// website's header.
/// With Reduce Motion the tickets stand still. Small waits (a button, a row) don't use it.
public struct TicketSpinner: View {
    /// What the spinner stands on.
    public enum Surface: Sendable {
        case brand
        case page
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let size: CGFloat
    private let surface: Surface

    /// - Parameter size: the mark's width and height, in points: 112 on the launch cover, 64 for
    ///   a page.
    public init(size: CGFloat = 64, on surface: Surface = .page) {
        self.size = size
        self.surface = surface
    }

    public var body: some View {
        let (ground, ink) =
            switch surface {
            case .brand: (Color(role: .bgBrand, in: .gym), Color(role: .fgOnBrand, in: .gym))
            case .page: (Color(role: .bgBrandPage, in: .gym), Color(role: .bgBrand, in: .gym))
            }
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let rock = reduceMotion ? 0 : TicketRock.amount(at: timeline.date.timeIntervalSinceReferenceDate)
            Canvas { context, canvas in
                TicketMark.draw(in: &context, size: canvas, rock: rock, ground: ground, ink: ink)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(Text("加载中", bundle: .module))
    }
}

/// The logo drawn on its 100 × 100 grid (brand-logo `b6-mark`): an outlined ticket behind, turned
/// 12°, and a filled one in front, turned −10°, with notches, a perforation and a W, both turning
/// about a point below them.
private enum TicketMark {
    /// The logo's ticket corners, on its 100-point canvas.
    private static let corner: Double = 8

    /// - Parameter rock: how far into `TicketRock`'s rock the tickets are.
    static func draw(in context: inout GraphicsContext, size: CGSize, rock: Double, ground: Color, ink: Color) {
        context.scaleBy(x: size.width / 100, y: size.height / 100)
        let pivot = CGPoint(x: 50, y: 92)

        var back = context
        turn(&back, by: 12 + TicketRock.backTurn * rock, about: pivot)
        let backTicket = Path(roundedRect: CGRect(x: 29.5, y: 15.5, width: 45, height: 68), cornerRadius: corner)
        back.fill(backTicket, with: .color(ground))
        back.stroke(backTicket, with: .color(ink), lineWidth: 3)

        var front = context
        front.translateBy(x: 0, y: -TicketRock.frontLift * rock)
        turn(&front, by: -10 + TicketRock.frontTurn * rock, about: pivot)
        front.fill(
            Path(roundedRect: CGRect(x: 26, y: 14, width: 48, height: 70), cornerRadius: corner), with: .color(ink))
        for notch in [26.0, 74] {
            front.fill(Path(ellipseIn: CGRect(x: notch - 5, y: 57, width: 10, height: 10)), with: .color(ground))
        }
        var perforation = Path()
        perforation.move(to: CGPoint(x: 35, y: 62))
        perforation.addLine(to: CGPoint(x: 65, y: 62))
        front.stroke(perforation, with: .color(ground), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
        var letter = front
        letter.clip(to: Path(CGRect(x: 0, y: 29, width: 100, height: 22)))
        var letterW = Path()
        letterW.addLines([
            CGPoint(x: 39.5, y: 24), CGPoint(x: 44.75, y: 54), CGPoint(x: 50, y: 24), CGPoint(x: 55.25, y: 54),
            CGPoint(x: 60.5, y: 24),
        ])
        letter.stroke(letterW, with: .color(ground), style: StrokeStyle(lineWidth: 5, lineJoin: .miter, miterLimit: 10))
    }

    private static func turn(_ context: inout GraphicsContext, by degrees: Double, about pivot: CGPoint) {
        context.translateBy(x: pivot.x, y: pivot.y)
        context.rotate(by: .degrees(degrees))
        context.translateBy(x: -pivot.x, y: -pivot.y)
    }
}
#endif
