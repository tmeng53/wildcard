#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import ScheduleDomain
import SportsUI
import SwiftUI

/// One day of a 出赛表 as a row: the weekday (今天 for today), the day's sport in a disc, its
/// name (or 休息), and a tick for a day trained or 请假 for a 请假条. The poster's lanes draw it,
/// and so does the back of a squadmate's player card, in whatever colours they sit on.
public struct ScheduleDayRow: View {
    /// The colours a row is drawn in.
    public struct Colors: Equatable {
        /// Words, the outline of a day planned and the fill of a day trained.
        public let ink: Color
        /// The glyph on a filled disc.
        public let onInk: Color
        /// A mark's disc (the tick's, 请假's) and its glyph.
        public let markDisc: Color
        public let markGlyph: Color

        public init(ink: Color, onInk: Color, markDisc: Color, markGlyph: Color) {
            (self.ink, self.onInk, self.markDisc, self.markGlyph) = (ink, onInk, markDisc, markGlyph)
        }
    }

    private let day: LocalDay
    private let isToday: Bool
    private let shown: PlanDay
    private let mark: DayMark
    private let colors: Colors
    /// A day off fades back, so the training days read first.
    private let fadesRest: Bool
    /// The mark at the row's end (the card's back) rather than after the name (the poster).
    private let marksAtEnd: Bool

    // From the approved design (出赛表 F, squadmate card E1).
    static let discSize: Double = 24
    private let markSize: Double = 17
    private let leaveTagHeight: Double = 20
    private let weekdayWidth: Double = 30
    private let restOpacity = 0.55
    private let outlineOpacity = 0.6
    private let restDotSize: Double = 5
    private let restDotOpacity = 0.35

    /// - Parameters:
    ///   - shown: what the row says, `shown(plan:mark:)` unless the day is being changed.
    public init(
        day: LocalDay, isToday: Bool, shown: PlanDay, mark: DayMark, colors: Colors, fadesRest: Bool = true,
        marksAtEnd: Bool = false
    ) {
        (self.day, self.isToday, self.shown, self.mark, self.colors) = (day, isToday, shown, mark, colors)
        (self.fadesRest, self.marksAtEnd) = (fadesRest, marksAtEnd)
    }

    /// What a day says: the sport logged on a day trained, else the plan.
    public static func shown(plan: PlanDay, mark: DayMark) -> PlanDay {
        if case .trained(let activity) = mark { .train(activity) } else { plan }
    }

    private var isFaded: Bool { fadesRest && shown == .rest }

    public var body: some View {
        HStack(spacing: Space.s - 2) {
            Group {
                if isToday {
                    Text(copy: "今天", bundle: .module)
                } else {
                    ScheduleLabels.weekday(day)
                }
            }
            .typeStyle(TypeRamp.label)
            // English's "Today" is a touch wider than the column: it shrinks rather than wraps.
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: weekdayWidth, alignment: .leading)
            disc
            ScheduleLabels.plan(shown)
                .typeStyle(TypeRamp.headline)
                .lineLimit(1)
                .opacity(isFaded ? restOpacity : 1)
            if marksAtEnd { Spacer(minLength: 0) }
            markView
            if !marksAtEnd { Spacer(minLength: 0) }
        }
        .foregroundStyle(colors.ink)
    }

    /// The day's sport: filled once trained, an outline while planned, a dot for a day off.
    @ViewBuilder
    private var disc: some View {
        let size = Self.discSize
        switch shown {
        case .rest:
            Circle()
                .fill(colors.ink.opacity(restDotOpacity))
                .frame(width: restDotSize, height: restDotSize)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        case .train(let activity):
            let trained = mark.isTrained
            Image(systemName: activity?.symbol ?? Sport.generalSymbol)
                .font(.system(size: size * 0.55, weight: .semibold))
                .foregroundStyle(trained ? colors.onInk : colors.ink)
                .frame(width: size, height: size)
                .background {
                    if trained {
                        Circle().fill(colors.ink)
                    } else {
                        Circle().strokeBorder(colors.ink.opacity(outlineOpacity), lineWidth: 1.5)
                    }
                }
                .accessibilityHidden(true)
        }
    }

    /// A tick for a day trained, 请假 for a 请假条.
    @ViewBuilder
    private var markView: some View {
        switch mark {
        case .trained:
            Image(systemName: "checkmark")
                .font(.system(size: markSize * 0.55, weight: .heavy))
                .foregroundStyle(colors.markGlyph)
                .frame(width: markSize, height: markSize)
                .background(colors.markDisc, in: Circle())
                .accessibilityHidden(true)
        case .disclaimer:
            Text(copy: "请假", bundle: .module)
                .typeStyle(TypeRamp.label)
                .foregroundStyle(colors.markGlyph)
                .padding(.horizontal, Space.xs - 1)
                .frame(height: leaveTagHeight)
                .background(colors.markDisc, in: Capsule())
        case .none:
            EmptyView()
        }
    }

    /// The row read out: 周三 跑步，训练.
    public var accessibilityText: Text {
        let weekday = isToday ? Text(copy: "今天", bundle: .module) : ScheduleLabels.weekday(day)
        let status: Text =
            switch mark {
            case .trained: Text(copy: "，训练", bundle: .module)
            case .disclaimer: Text(copy: "，请假", bundle: .module)
            case .none: Text(verbatim: "")
            }
        return Text(copy: "\(weekday) \(ScheduleLabels.plan(shown))\(status)", bundle: .module)
    }
}
#endif
