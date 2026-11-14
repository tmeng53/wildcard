#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// A 外卡 for a streak still going (Tracy, 2026-11-10): the logo's front ticket, upright, with the
/// days written where its W is and the streak's mark on the stub under the tear: a dumbbell for
/// days trained, a bowl for days with a 健康餐. The player card shows one per streak going and none
/// for a broken one.
public struct StreakTicket: View {
    public enum Streak: Sendable {
        case training, meals
    }

    private let days: Int
    private let streak: Streak
    private let ink: ColorRole
    private let ground: ColorRole
    @Environment(\.sceneTheme) private var theme

    /// `ink` fills the ticket; `ground`, what it stands on, shows through its notches, and the
    /// days, tear and mark are written in it.
    public init(days: Int, streak: Streak, ink: ColorRole = .fgOnBrand, on ground: ColorRole = .bgBrand) {
        (self.days, self.streak, self.ink, self.ground) = (days, streak, ink, ground)
    }

    /// The ticket's area on the logo's grid, as `LogoTicket` draws it.
    private static let area = CGRect(x: 25, y: 13, width: 50, height: 72)
    public static let size = CGSize(width: 32, height: 46)

    public var body: some View {
        let ground = Color(role: ground, in: theme)
        Canvas { context, canvas in
            context.scaleBy(x: canvas.width / Self.area.width, y: canvas.height / Self.area.height)
            context.translateBy(x: -Self.area.minX, y: -Self.area.minY)
            TicketMark.drawFront(in: &context, ground: ground, ink: Color(role: ink, in: theme), letter: 0)
        }
        .overlay {
            GeometryReader { ticket in
                let unit = ticket.size.height / Self.area.height
                Text(verbatim: "\(days)")
                    .typeStyle(TypeRamp.scoreInline)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(ground)
                    // Where the logo writes its W, above the tear (y 62 on its grid).
                    .frame(width: ticket.size.width, height: (62 - 16) * unit)
                    .position(x: ticket.size.width / 2, y: ((16 + 62) / 2 - Self.area.minY) * unit)
                mark
                    .fill(ground)
                    .frame(width: 14 * unit, height: 14 * unit)
                    // The stub, between the tear and the ticket's foot (y 84).
                    .position(x: ticket.size.width / 2, y: ((62 + 84) / 2 - Self.area.minY) * unit)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityElement()
        .accessibilityLabel(label)
    }

    private var mark: AnyShape {
        switch streak {
        case .training: AnyShape(DumbbellMark())
        case .meals: AnyShape(BowlMark())
        }
    }

    private var label: Text {
        switch streak {
        case .training: Text(copy: "streak.training \(days)", bundle: .module)
        case .meals: Text(copy: "streak.meals \(days)", bundle: .module)
        }
    }
}

/// A dumbbell lying flat, on a 24-point grid: two plates each side of a bar.
private struct DumbbellMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // The outer plates, the inner plates and the bar between them.
        let plates: [(CGRect, Double)] = [
            (CGRect(x: 1, y: 9, width: 2.5, height: 6), 1), (CGRect(x: 4, y: 6, width: 3.5, height: 12), 1.2),
            (CGRect(x: 7.5, y: 10.75, width: 9, height: 2.5), 0), (CGRect(x: 16.5, y: 6, width: 3.5, height: 12), 1.2),
            (CGRect(x: 20.5, y: 9, width: 2.5, height: 6), 1),
        ]
        for (plate, corner) in plates {
            path.addRoundedRect(in: plate, cornerSize: CGSize(width: corner, height: corner))
        }
        return path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
            .offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// A rice bowl, on a 24-point grid: the rice heaped over the rim, the bowl and its foot.
private struct BowlMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // The rice.
        path.move(to: CGPoint(x: 5, y: 6.5))
        path.addQuadCurve(to: CGPoint(x: 19, y: 6.5), control: CGPoint(x: 12, y: -0.5))
        path.closeSubpath()
        // The bowl, narrowing to its foot.
        path.move(to: CGPoint(x: 2, y: 9))
        path.addLine(to: CGPoint(x: 22, y: 9))
        path.addQuadCurve(to: CGPoint(x: 14, y: 18.1), control: CGPoint(x: 21.5, y: 17))
        path.addLine(to: CGPoint(x: 14, y: 20))
        path.addLine(to: CGPoint(x: 10, y: 20))
        path.addLine(to: CGPoint(x: 10, y: 18.1))
        path.addQuadCurve(to: CGPoint(x: 2, y: 9), control: CGPoint(x: 2.5, y: 17))
        path.closeSubpath()
        path.addRoundedRect(in: CGRect(x: 6.5, y: 20, width: 11, height: 2), cornerSize: CGSize(width: 1, height: 1))
        return path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
            .offsetBy(dx: rect.minX, dy: rect.minY)
    }
}
#endif
