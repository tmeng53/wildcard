#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// A score like `14/22` in Barlow: the count in ink, the goal a weight lighter, a little over half
/// the size and in subtle ink. One `.hero` score per screen.
public struct Score: View {
    public enum Size: Sendable {
        case hero
        case card
        case inline
        /// A count beside its label, with no goal.
        case small

        var style: TypeStyle {
            switch self {
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
    private let onInk: Bool

    /// Leave out `goal` for a count on its own (一共练了 46). `onInk` sets it white on a `bgInk`
    /// surface, its goal in muted ink.
    public init(count: Int, goal: Int? = nil, size: Size, onInk: Bool = false) {
        self.count = count
        self.goal = goal
        self.size = size
        self.onInk = onInk
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(verbatim: "\(count)")
                .typeStyle(size.style)
                .foregroundStyle(Color(role: onInk ? .fgOnInk : .fgDefault, in: theme))
                .contentTransition(.numericText(value: Double(count)))
            if let goal {
                Text(verbatim: "/\(goal)")
                    .typeStyle(TypeRamp.denominator(of: size.style))
                    .foregroundStyle(Color(role: onInk ? .fgMuted : .fgSubtle, in: theme))
            }
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: goal.map { "\(count)/\($0)" } ?? "\(count)"))
    }
}
#endif
