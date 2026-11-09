#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// The logo's two tickets rocking apart and back on a beat (`TicketRock`): any whole-page load.
/// On `.brand` (graphite) the front ticket is white; on `.page`
/// (the brand's light page) the colours swap, the back ticket only an outline, as on the
/// website's header. On `.light(role)` they are graphite on that light role of the screen's scene
/// (a page's white, a card's mist), for a load inside a screen.
/// With Reduce Motion the tickets stand still. Small waits (a button, a row) don't use it.
public struct TicketSpinner: View {
    /// What the spinner stands on.
    public enum Surface: Sendable {
        case brand
        case page
        /// A light background role of the screen's scene, such as `.bgCanvas` or `.bgSubtle`.
        case light(ColorRole)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sceneTheme) private var theme
    private let size: CGFloat
    private let surface: Surface

    /// - Parameter size: the mark's width and height, in points: 112 on the launch cover, 64 for
    ///   a page, 32 for a photo.
    public init(size: CGFloat = 64, on surface: Surface = .page) {
        self.size = size
        self.surface = surface
    }

    public var body: some View {
        let (ground, ink) =
            switch surface {
            case .brand: (Color(role: .bgBrand, in: .gym), Color(role: .fgOnBrand, in: .gym))
            case .page: (Color(role: .bgBrandPage, in: .gym), Color(role: .bgBrand, in: .gym))
            case .light(let role): (Color(role: role, in: theme), Color(role: .bgBrand, in: theme))
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

/// The logo's two tickets standing still: a mark, such as the seal on the coach's letter (交接信)
/// and its letterhead. `ground` is what it stands on, the back ticket filled with it; `ink` draws
/// the front ticket and the back one's outline.
public struct TicketLogo: View {
    private let ground: ColorRole
    private let ink: ColorRole
    @Environment(\.sceneTheme) private var theme

    public init(on ground: ColorRole = .bgCanvas, ink: ColorRole = .bgBrand) {
        self.ground = ground
        self.ink = ink
    }

    public var body: some View {
        Canvas { context, canvas in
            TicketMark.draw(
                in: &context, size: canvas, rock: 0, ground: Color(role: ground, in: theme),
                ink: Color(role: ink, in: theme))
        }
        .accessibilityHidden(true)
    }
}

/// The logo drawn on its 100 × 100 grid (brand-logo `b6-mark`): an outlined ticket behind, turned
/// 12°, and a filled one in front, turned −10°, with notches, a perforation and a W, both turning
/// about a point below them.
enum TicketMark {
    /// The logo's ticket corners, on its 100-point canvas.
    private static let corner: Double = 8

    /// - Parameters:
    ///   - rock: how far into `TicketRock`'s rock the tickets are.
    ///   - letter: how much of the W shows, 1 for all of it.
    ///   - check: how much of `TicketCheck`'s check is drawn where the W was.
    static func draw(
        in context: inout GraphicsContext, size: CGSize, rock: Double, ground: Color, ink: Color,
        letter letterOpacity: Double = 1, check: Double = 0
    ) {
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
        drawFront(in: &front, ground: ground, ink: ink, letter: letterOpacity, check: check)
    }

    /// The front ticket, upright on the logo's 100-point grid: filled in `ink`, with notches, a
    /// perforation and a W in `ground`.
    static func drawFront(
        in front: inout GraphicsContext, ground: Color, ink: Color, letter letterOpacity: Double = 1, check: Double = 0
    ) {
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
        letter.opacity = letterOpacity
        letter.clip(to: Path(CGRect(x: 0, y: 29, width: 100, height: 22)))
        var letterW = Path()
        letterW.addLines([
            CGPoint(x: 39.5, y: 24), CGPoint(x: 44.75, y: 54), CGPoint(x: 50, y: 24), CGPoint(x: 55.25, y: 54),
            CGPoint(x: 60.5, y: 24),
        ])
        letter.stroke(letterW, with: .color(ground), style: StrokeStyle(lineWidth: 5, lineJoin: .miter, miterLimit: 10))
        if check > 0 {
            var mark = Path()
            mark.addLines([CGPoint(x: 38, y: 38), CGPoint(x: 47, y: 47), CGPoint(x: 63, y: 29)])
            front.stroke(
                mark.trimmedPath(from: 0, to: min(check, 1)), with: .color(ground),
                style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
        }
    }

    private static func turn(_ context: inout GraphicsContext, by degrees: Double, about pivot: CGPoint) {
        context.translateBy(x: pivot.x, y: pivot.y)
        context.rotate(by: .degrees(degrees))
        context.translateBy(x: -pivot.x, y: -pivot.y)
    }
}

/// The logo's front ticket standing alone, 25 × 36 points: a day on 外卡记录's
/// streaks, punched in one at a time. White with graphite cut-outs on a graphite tile.
public struct LogoTicket: View {
    private let ground: ColorRole
    private let ink: ColorRole
    @Environment(\.sceneTheme) private var theme

    /// `ink` fills the ticket; `ground`, what it stands on, shows through its notches, perforation
    /// and W.
    public init(ink: ColorRole = .fgOnBrand, on ground: ColorRole = .bgBrand) {
        (self.ink, self.ground) = (ink, ground)
    }

    /// The ticket's area on the logo's grid, with half a point to spare around it.
    private static let area = CGRect(x: 25, y: 13, width: 50, height: 72)
    public static let size = CGSize(width: 25, height: 36)

    public var body: some View {
        Canvas { context, canvas in
            context.scaleBy(x: canvas.width / Self.area.width, y: canvas.height / Self.area.height)
            context.translateBy(x: -Self.area.minX, y: -Self.area.minY)
            TicketMark.drawFront(
                in: &context, ground: Color(role: ground, in: theme), ink: Color(role: ink, in: theme))
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityHidden(true)
    }
}
#endif
