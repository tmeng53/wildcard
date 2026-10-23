#if os(iOS)
import AvatarUI
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import SportsUI
import SwiftUI

/// The 今日赛况 tag, the squad card's last row from the evening on: the brand's colour with a dot
/// until today's recap has been opened, quiet grey after (the approved 今日赛况, version 4).
struct RecapTag: View {
    @Environment(\.sceneTheme) private var theme
    let recap: DayRecap
    let isSeen: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: Space.xxs) {
                Image(systemName: "moon.fill")
                    .font(.system(size: RecapMetrics.moon))
                    .foregroundStyle(Color(role: isSeen ? .fgSubtle : .fgOnBrand, in: theme))
                Text("今日赛况", bundle: .module)
                    .typeStyle(TypeRamp.footnoteEmphasis)
                    .foregroundStyle(Color(role: isSeen ? .fgDefault : .fgOnBrand, in: theme))
                Text(verbatim: "\(recap.showedUp)/\(recap.members)")
                    .typeStyle(TypeRamp.scoreSmall)
                    .monospacedDigit()
                    .foregroundStyle(Color(role: isSeen ? .fgDefault : .fgOnBrand, in: theme))
            }
            .padding(.leading, Space.xs)
            .padding(.trailing, Space.s)
            .frame(height: Sizing.tag)
            .background(Color(role: isSeen ? .bgSubtle : .bgBrand, in: theme), in: Capsule())
            .overlay(alignment: .topTrailing) {
                if !isSeen {
                    Circle()
                        .fill(Color(role: .fgOnBrand, in: theme))
                        .frame(width: RecapMetrics.dot, height: RecapMetrics.dot)
                        .overlay(Circle().strokeBorder(Color(role: .bgBrand, in: theme), lineWidth: 2))
                        .offset(x: 2, y: -2)
                }
            }
            .frame(minHeight: Sizing.tag)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSeen ? Text("今日赛况", bundle: .module) : Text("今日赛况，还没看", bundle: .module))
        .accessibilityValue(Text(verbatim: "\(recap.showedUp)/\(recap.members)"))
        .accessibilityIdentifier("today.recap.tag")
    }
}

/// 今日赛况 opened: the squad's day as a box score in the card's place. One row for each member
/// who trained (by who went first), took a 请假条 or rests by plan; nobody else. 收起 folds it.
struct DayRecapCard: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let recap: DayRecap
    let day: Date
    /// Each row's head and name.
    let member: @MainActor (MemberID) -> (head: CharacterPlayer?, name: String)
    let close: () -> Void
    /// The score rolls up from nothing as the card opens.
    @State private var shown = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .bottom, spacing: Space.s) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    SectionLabel(Text("今日赛况", bundle: .module))
                    Text(day, format: .dateTime.month().day().weekday(.abbreviated))
                        .typeStyle(TypeRamp.headline)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Score(count: shown, goal: recap.members, size: .hero)
            }
            if recap.rows.isEmpty {
                Text("今天小队在养精蓄锐，明天见", bundle: .module)
                    .typeStyle(TypeRamp.callout)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
            } else {
                Grid(alignment: .leading, horizontalSpacing: Space.xs, verticalSpacing: 0) {
                    ForEach(recap.rows, id: \.member) { row in
                        let who = member(row.member)
                        GridRow {
                            // The head cell sets the row's height.
                            head(who.head)
                                .frame(height: RecapMetrics.row)
                            Text(verbatim: who.name)
                                .typeStyle(TypeRamp.calloutEmphasis)
                                .foregroundStyle(Color(role: .fgDefault, in: theme))
                                .lineLimit(1)
                            what(row.kind)
                        }
                    }
                }
            }
            HStack(spacing: Space.s) {
                if recap.healthyMeals + recap.cheatMeals > 0 {
                    Text("健康餐 \(recap.healthyMeals) · 放纵餐 \(recap.cheatMeals)", bundle: .module)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                }
                Spacer(minLength: 0)
                Button(action: close) {
                    Text("收起", bundle: .module)
                        .typeStyle(TypeRamp.footnoteEmphasis)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .padding(.horizontal, Space.s)
                        .frame(height: Sizing.tag)
                        .background(Color(role: .bgSubtle, in: theme), in: Capsule())
                        .frame(minHeight: Sizing.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today.recap.close")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(on: .scene)
        .padding(.horizontal, Space.pageMargin)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.recap")
        .onAppear {
            withAnimation(.wildcard(Motion.celebrate, reduceMotion: reduceMotion).delay(0.15)) {
                shown = recap.showedUp
            }
        }
        .onChange(of: recap.showedUp) { _, count in shown = count }
    }

    private func head(_ player: CharacterPlayer?) -> some View {
        Circle()
            .fill(Color(role: .bgSubtle, in: theme))
            .overlay { if let player { CharacterHead(player: player) } }
            .frame(width: RecapMetrics.head, height: RecapMetrics.head)
            .clipShape(Circle())
    }

    @ViewBuilder private func what(_ kind: DayRecap.RowKind) -> some View {
        switch kind {
        case .trained(let activity, let meal):
            HStack(spacing: Space.xs) {
                Text(verbatim: activity.localizedName)
                    .typeStyle(TypeRamp.calloutEmphasis)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .lineLimit(1)
                if let meal {
                    Group {
                        switch meal {
                        case .healthyMeal: Text("健康餐", bundle: .module)
                        case .cheatMeal: Text("放纵餐", bundle: .module)
                        }
                    }
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                }
            }
        case .disclaimer(let note):
            HStack(spacing: Space.xs) {
                MoonTag(label: Text("请假条", bundle: .module))
                Text(verbatim: note)
                    .typeStyle(TypeRamp.callout)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        case .restDay:
            MoonTag(label: Text("休息日", bundle: .module))
        }
    }
}

/// A grey tag with a moon: a 请假条 or a rest day, as the feed marks them.
private struct MoonTag: View {
    @Environment(\.sceneTheme) private var theme
    let label: Text

    var body: some View {
        HStack(spacing: Space.xxs) {
            Image(systemName: "moon.fill")
                .font(.system(size: RecapMetrics.tagMoon))
                .foregroundStyle(Color(role: .fgSubtle, in: theme))
            label
                .typeStyle(TypeRamp.label)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
        }
        .padding(.horizontal, Space.xs)
        .frame(height: RecapMetrics.tagHeight)
        .background(Color(role: .bgSubtle, in: theme), in: Capsule())
        .fixedSize()
    }
}

/// Sizes that belong to 今日赛况 alone.
private enum RecapMetrics {
    static let moon: Double = 11
    static let dot: Double = 10
    static let head: Double = 22
    static let row: Double = 32
    static let tagHeight: Double = 20
    static let tagMoon: Double = 9
}
#endif
