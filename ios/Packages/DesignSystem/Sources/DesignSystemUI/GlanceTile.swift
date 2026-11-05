#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// A brand tile that opens a page of the member's own: a number and its caption on the left, a
/// glimpse of the page on the right (the week's days, the newest posts) and a chevron, on
/// graphite. 我 stacks them under the player card, all as wide as the page and as tall as each
/// other, so they read as one set.
public struct GlanceTile<Glimpse: View>: View {
    @Environment(\.sceneTheme) private var theme
    private let figure: Text
    private let figureStyle: TypeStyle
    private let caption: Text
    private let action: () -> Void
    private let glimpse: Glimpse

    /// `figure` is the tile's number (W45, 128), in `figureStyle`: `scoreWeek` for a week,
    /// `scoreCard` for a count.
    public init(
        figure: Text, figureStyle: TypeStyle = TypeRamp.scoreCard, caption: Text, action: @escaping () -> Void,
        @ViewBuilder glimpse: () -> Glimpse
    ) {
        self.figure = figure
        self.figureStyle = figureStyle
        self.caption = caption
        self.action = action
        self.glimpse = glimpse()
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                VStack(alignment: .leading, spacing: 0) {
                    figure
                        .typeStyle(figureStyle)
                        .foregroundStyle(Color(role: .fgOnBrand, in: theme))
                    caption
                        .typeStyle(TypeRamp.footnoteEmphasis)
                        .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
                }
                .lineLimit(1)
                .fixedSize()
                glimpse
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(.system(size: Sizing.smallIcon, weight: .semibold))
                    .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
                    .accessibilityHidden(true)
            }
            .padding(.leading, Space.m)
            .padding(.trailing, Space.s)
            .frame(minHeight: GlanceTileMetrics.height)
            .background(
                Color(role: .bgBrand, in: theme),
                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// A week's seven days in a `GlanceTile`'s glimpse (我's 出赛表): each day's name over its mark,
/// in white on graphite, today's heavier. A day with a 练了 is a white disc with a tick; a
/// training day not done (yet, or gone by) a thin ring, never red; a rest day a moon.
public struct GlanceWeekDays: View {
    /// One day, Monday first.
    public struct Day: Hashable, Sendable {
        public let status: WeekDayStatus
        public let isToday: Bool

        public init(status: WeekDayStatus, isToday: Bool) {
            (self.status, self.isToday) = (status, isToday)
        }
    }

    @Environment(\.sceneTheme) private var theme
    private let days: [Day]

    public init(_ days: [Day]) {
        self.days = days
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { weekday, day in
                VStack(spacing: Space.xxs) {
                    DayCircle.name(weekday)
                        .typeStyle(day.isToday ? TypeRamp.tabSelected : TypeRamp.tab)
                        .foregroundStyle(Color(role: day.isToday ? .fgOnBrand : .fgOnInkMuted, in: theme))
                        .fixedSize()
                    mark(day)
                        .frame(width: GlanceTileMetrics.day, height: GlanceTileMetrics.day)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder private func mark(_ day: Day) -> some View {
        let white = Color(role: .fgOnBrand, in: theme)
        let quiet = Color(role: .fgOnInkMuted, in: theme)
        switch day.status {
        case .trained(let symbol):
            Circle()
                .fill(white)
                .overlay {
                    Image(systemName: symbol ?? "checkmark")
                        .font(.system(size: Self.glyph, weight: .bold))
                        .foregroundStyle(Color(role: .bgBrand, in: theme))
                }
        case .excused:
            Text("假", bundle: .module)
                .typeStyle(TypeRamp.label)
                .foregroundStyle(day.isToday ? white : quiet)
        case .restDay:
            Image(systemName: "moon.fill")
                .font(.system(size: Self.glyph, weight: .semibold))
                .foregroundStyle(day.isToday ? white : quiet)
        case .open, .planned:
            Circle()
                .strokeBorder(
                    day.isToday ? white : quiet,
                    lineWidth: day.isToday ? SquadCardMetrics.todayStroke : Sizing.selectionStroke
                )
                .overlay {
                    if case .planned(let symbol) = day.status {
                        Image(systemName: symbol)
                            .font(.system(size: Self.glyph, weight: .semibold))
                            .foregroundStyle(day.isToday ? white : quiet)
                    }
                }
        }
    }

    private static var glyph: Double { 11 }
}

/// The tile's sizes, for what goes in its glimpse.
public enum GlanceTileMetrics {
    /// Every tile is at least this tall, so a set lines up.
    public static let height: Double = 76
    /// A post's thumbnail in a glimpse.
    public static let thumbnail: Double = 44
    /// A day's circle in a glimpse.
    public static let day: Double = 22
}
#endif
