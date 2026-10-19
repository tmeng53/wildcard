#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// A score like `18/25`: the count in signature text, the goal smaller in tertiary ink.
public struct Score: View {
    @Environment(\.sceneTheme) private var theme
    let count: Int
    let goal: Int
    let countStyle: TypeStyle
    let goalStyle: TypeStyle

    public init(count: Int, goal: Int, countStyle: TypeStyle, goalStyle: TypeStyle) {
        self.count = count
        self.goal = goal
        self.countStyle = countStyle
        self.goalStyle = goalStyle
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(verbatim: "\(count)")
                .typeStyle(countStyle)
                .foregroundStyle(Color(role: .signatureText, in: theme))
            Text(verbatim: "/\(goal)")
                .typeStyle(goalStyle)
                .foregroundStyle(Color(role: .textTertiary, in: theme))
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(count)/\(goal)"))
    }
}
#endif
