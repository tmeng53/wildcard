#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import HomeWidgetDomain
import SportsUI
import SwiftUI

/// 本周出赛表's white card at its foot (Tracy, 2026-11-13): 今日挑战, what to do and the amount
/// large in the scene's colour with its unit, and whether I took it up or did it; before the coach
/// set one, today's plan; while the squad has no coach, 招聘教练. `compact` is the small widget's,
/// two lines and no icon.
struct ScheduleChallengeCard: View {
    @Environment(\.sceneTheme) private var theme
    let board: WidgetBoard
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? Space.xs : Space.s) {
            if !compact {
                Image(systemName: cardSymbol)
                    .font(.system(size: CardMetrics.cardGlyph, weight: .semibold))
                    .foregroundStyle(Color(role: .fgAccent, in: theme))
                    .frame(width: CardMetrics.cardIcon, height: CardMetrics.cardIcon)
                    .background(Color(role: .bgSubtle, in: theme), in: Circle())
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 0) {
                cardLabel
                    .typeStyle(compact ? TypeRamp.tab : TypeRamp.caption)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .lineLimit(1)
                cardTitle
                    .typeStyle(compact ? TypeRamp.footnoteEmphasis : TypeRamp.calloutEmphasis)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .lineLimit(compact ? 2 : 1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            cardTrailing(compact: compact)
        }
        .padding(.leading, compact ? Space.s : Space.s - 2)
        .padding(.trailing, compact ? Space.s : Space.xs + 2)
        .padding(.vertical, compact ? Space.xs : 0)
        .frame(minHeight: compact ? CardMetrics.smallCard : CardMetrics.mediumCard)
        .frame(height: compact ? nil : CardMetrics.mediumCard)
        .background(
            Color(role: .bgCanvas, in: theme), in: RoundedRectangle(cornerRadius: Radius.ticket, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("widget.challenge")
    }

    private var challenge: CoachPageCard.Challenge? { board.challenge?.challenge }

    /// The card's icon: the flag, a tick once it is done, the moon on a rest day, + without a coach.
    private var cardSymbol: String {
        if board.coach == nil { return "plus" }
        if let challenge { return challenge.completedBy == nil ? "flag.fill" : "checkmark" }
        return board.planToday?.status == .restDay ? "moon.fill" : "flag.fill"
    }

    private var cardLabel: Text {
        if board.coach == nil { return Text(copy: "今日挑战", bundle: .module) }
        guard let challenge else {
            return board.planToday?.status == .restDay
                ? Text(copy: "今天", bundle: .module) : Text(copy: "今日挑战", bundle: .module)
        }
        if challenge.completedBy != nil { return Text(copy: "今日挑战 · 完成", bundle: .module) }
        switch challenge.answer {
        case .accepted: return Text(copy: "今日挑战 · 已接受", bundle: .module)
        case .declined: return Text(copy: "今日挑战 · 没接", bundle: .module)
        case nil: return Text(copy: "今日挑战", bundle: .module)
        }
    }

    private var cardTitle: Text {
        if board.coach == nil { return Text(copy: "请个教练，每天出挑战", bundle: .module) }
        if let challenge { return Text(verbatim: challenge.title) }
        guard board.planToday?.status == .restDay else { return Text(copy: "等教练出题", bundle: .module) }
        if let tomorrow = board.planTomorrow, tomorrow.status == .open, let activity = tomorrow.activity {
            return Text(copy: "好好休息，明天", bundle: .module) + activity.cardName
        }
        return Text(copy: "好好休息", bundle: .module)
    }

    /// The amount large in the scene's colour with its unit; without a coach, 招聘教练.
    @ViewBuilder private func cardTrailing(compact: Bool) -> some View {
        if board.coach == nil {
            Text(copy: "招聘教练", bundle: .module)
                .typeStyle(TypeRamp.captionEmphasis)
                .foregroundStyle(Color(role: .fgOnInk, in: theme))
                .padding(.horizontal, Space.s - 2)
                .padding(.vertical, Space.xxs + 1)
                .background(Color(role: .bgInk, in: theme), in: Capsule())
                .fixedSize()
        } else if let challenge, let amount = challenge.amount {
            HStack(alignment: .firstTextBaseline, spacing: Space.xxs / 2) {
                Text(verbatim: "\(amount)")
                    .typeStyle(compact ? TypeRamp.scoreInline : TypeRamp.scoreWeek)
                if let unit = challenge.unit {
                    Text(verbatim: unit)
                        .typeStyle(TypeRamp.captionEmphasis)
                }
            }
            .foregroundStyle(Color(role: .fgAccent, in: theme))
            .lineLimit(1)
            .fixedSize()
        }
    }

    /// Sizes that belong to the card only.
    private enum CardMetrics {
        static let smallCard: Double = 46
        static let mediumCard: Double = 50
        static let cardIcon: Double = 26
        static let cardGlyph: Double = 13
    }
}

extension ScheduleWidget {
    /// The widget's background, which the card stands on: the 出赛表 poster's grid on the scene's colour, edge to edge.
    public struct Backdrop: View {
        @Environment(\.sceneTheme) private var theme

        public init() {}

        public var body: some View {
            let line = Color(role: .fgOnAccent, in: theme).opacity(0.08)
            Canvas { context, size in
                var grid = Path()
                let step = 17.0
                for column in stride(from: step, to: size.width, by: step) {
                    grid.move(to: CGPoint(x: column, y: 0))
                    grid.addLine(to: CGPoint(x: column, y: size.height))
                }
                for row in stride(from: step, to: size.height, by: step) {
                    grid.move(to: CGPoint(x: 0, y: row))
                    grid.addLine(to: CGPoint(x: size.width, y: row))
                }
                context.stroke(grid, with: .color(line), lineWidth: 1)
            }
            .background(Color(role: .bgAccent, in: theme))
        }
    }
}
#endif
