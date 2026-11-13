#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// The squad's goal as one cell a day, as many cells as the goal and as many filled as the days
/// trained, never past full (the score's 「+N」 tag shows days past it). Ink on a light grey that
/// reads on the card's glass, never red.
public struct DayCells: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let filled: Int
    let total: Int

    public init(filled: Int, total: Int) {
        self.filled = filled
        self.total = total
    }

    public var body: some View {
        let spacing = total > 40 ? SquadCardMetrics.denseCellSpacing : SquadCardMetrics.cellSpacing
        HStack(spacing: spacing) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                RoundedRectangle(cornerRadius: Sizing.progress / 4, style: .continuous)
                    .fill(Color(role: index < filled ? .fgDefault : .fgSubtle, in: theme))
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
                        // still a full tap target, reaching up and only halfway down to the
                        // grabber under the row, which takes the rest.
                        .frame(width: SquadCardMetrics.dot * 2, height: Space.cardPadding)
                        .contentShape(Self.tapArea)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    item == .squad ? Text(copy: "小队", bundle: .module) : Text(copy: "我这周", bundle: .module)
                )
                .accessibilityAddTraits(item == page ? .isSelected : [])
                .accessibilityIdentifier("squadcard.page.\(item == .squad ? "squad" : "mine")")
            }
        }
        .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: page)
    }

    /// A dot's tap area: a full target wide and above the row, and half the gap below it.
    private static var tapArea: Path {
        let reach = (Sizing.minimumTapTarget - Space.cardPadding) / 2
        return Path(
            CGRect(
                x: -reach, y: -reach, width: SquadCardMetrics.dot * 2 + reach * 2,
                height: reach + Space.cardPadding + Space.xs / 2))
    }
}

/// The short bar a sheet has at its edge, saying the card folds and opens: on the squad card
/// a button that folds it, on the folded capsule just the mark (the capsule is the button).
struct Grabber: View {
    @Environment(\.sceneTheme) private var theme
    var label: Text?
    var action: (() -> Void)?

    var body: some View {
        if let action, let label {
            Button(action: action) { bar }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
        } else {
            bar.accessibilityHidden(true)
        }
    }

    private var bar: some View {
        Capsule()
            .fill(Color(role: .fgDefault, in: theme).opacity(Self.opacity))
            .frame(width: Self.size.width, height: Self.size.height)
            // A full tap target around the thin bar.
            .frame(width: Sizing.minimumTapTarget * 2, height: Self.size.height)
            .contentShape(Rectangle().inset(by: -(Sizing.minimumTapTarget - Self.size.height) / 2))
    }

    static let size = CGSize(width: 36, height: 5)
    /// Ink this faint reads as the system's grabber on glass.
    private static let opacity = 0.22
}

/// The squad page's top: its label and title on the left, the big score on the right. Given
/// `open`, the title is a button with a chevron after it.
struct PageHeader: View {
    @Environment(\.sceneTheme) private var theme
    let label: Text
    let title: String
    let count: Int
    let goal: Int
    let unit: Text  // A word after the score (次).
    var open: (() -> Void)?

    var body: some View {
        HStack(alignment: .bottom, spacing: Space.s) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                SectionLabel(label)
                if let open {
                    Button(action: open) {
                        HStack(spacing: Space.xxs) {
                            titleText
                            Image(systemName: "chevron.right")
                                .font(.system(size: Sizing.smallIcon - 2, weight: .semibold))
                                .foregroundStyle(Color(role: .fgMuted, in: theme))
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityIdentifier("squadcard.squad")
                } else {
                    titleText
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
                Score(count: count, goal: goal, size: .goal)
                unit
                    .typeStyle(TypeRamp.denominator(of: TypeRamp.scoreGoal))
                    .foregroundStyle(Color(role: .fgSubtle, in: theme))
                if count > goal {  // 训练 past the goal as a small 「+N」 tag after the score.
                    InkTag(Text(verbatim: "+\(count - goal)"), height: CoachTag.Size.regular.height)
                        .accessibilityLabel(Text(copy: "多练 \(count - goal) 次", bundle: .module))
                        .accessibilityIdentifier("squadcard.extra")
                }
            }
        }
    }

    private var titleText: some View {
        Text(verbatim: title)
            .typeStyle(TypeRamp.headline)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .lineLimit(1)
    }
}
#endif
