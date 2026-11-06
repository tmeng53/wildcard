#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// The squad's goal as one cell a day, as many cells as the goal and as many filled as the days
/// trained, never past full. Ink on the bar's subtle track, never red.
struct DayCells: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let filled: Int
    let total: Int

    var body: some View {
        let spacing = total > 40 ? SquadCardMetrics.denseCellSpacing : SquadCardMetrics.cellSpacing
        HStack(spacing: spacing) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                RoundedRectangle(cornerRadius: Sizing.progress / 4, style: .continuous)
                    .fill(Color(role: index < filled ? .fgDefault : .bgSubtle, in: theme))
            }
        }
        .frame(height: Sizing.progress)
        .animation(.wildcard(Motion.page, reduceMotion: reduceMotion), value: filled)
        .accessibilityHidden(true)
    }
}

/// Two dots at the card's foot, the current page's solid. Tapping one goes to it.
struct PageDots: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var page: SquadCardPage

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SquadCardPage.allCases, id: \.self) { item in
                Button {
                    withAnimation(.wildcard(Motion.page, reduceMotion: reduceMotion)) { page = item }
                } label: {
                    Circle()
                        .fill(Color(role: .fgOnScene, in: theme).opacity(item == page ? 1 : 0.25))
                        .frame(width: SquadCardMetrics.dot, height: SquadCardMetrics.dot)
                        // 6 apart to the eye, in a row as tall as the card's padding, each
                        // still a full tap target tall.
                        .frame(width: SquadCardMetrics.dot * 2, height: Space.cardPadding)
                        .contentShape(Rectangle().inset(by: -(Sizing.minimumTapTarget - Space.cardPadding) / 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item == .squad ? Text("小队", bundle: .module) : Text("我这周", bundle: .module))
                .accessibilityAddTraits(item == page ? .isSelected : [])
                .accessibilityIdentifier("squadcard.page.\(item == .squad ? "squad" : "mine")")
            }
        }
        .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: page)
    }
}
#endif
