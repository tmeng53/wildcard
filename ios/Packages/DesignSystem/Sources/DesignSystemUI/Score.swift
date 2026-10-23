#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// A score like `14/22` in Barlow: the count in ink, the goal a weight lighter, a little over half
/// the size and in subtle ink. One `.hero` score per screen.
public struct Score: View {
    public enum Size: Sendable {
        /// A 战报 page's one number, full screen.
        case story
        /// The 战报's last page when the scene pick shares it.
        case ending
        case hero
        case card
        case inline
        /// A count beside its label, with no goal.
        case small

        var style: TypeStyle {
            switch self {
            case .story: TypeRamp.scoreStory
            case .ending: TypeRamp.scoreEnding
            case .hero: TypeRamp.scoreHero
            case .card: TypeRamp.scoreCard
            case .inline: TypeRamp.scoreInline
            case .small: TypeRamp.scoreSmall
            }
        }
    }

    @Environment(\.sceneTheme) private var theme
    private let count: Int
    private let goal: Int?
    private let size: Size

    /// Leave out `goal` for a count on its own (一共练了 46).
    public init(count: Int, goal: Int? = nil, size: Size) {
        self.count = count
        self.goal = goal
        self.size = size
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(verbatim: "\(count)")
                .typeStyle(size.style)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .contentTransition(.numericText(value: Double(count)))
            if let goal {
                Text(verbatim: "/\(goal)")
                    .typeStyle(TypeRamp.denominator(of: size.style))
                    .foregroundStyle(Color(role: .fgSubtle, in: theme))
            }
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: goal.map { "\(count)/\($0)" } ?? "\(count)"))
    }
}
#endif
