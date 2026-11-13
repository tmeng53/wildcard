#if os(iOS)
import DesignSystem
import DesignSystemUI
import SwiftUI

/// One sport or kind in a list that compares them: its symbol in a circle, its name, an optional
/// accessory (the 战报's heads), a bar against the most-counted one and its count with a unit.
/// The 战报's 项目 counts days with heads beside them; a place's page counts 次 without them
/// (Tracy, 2026-11-12: the same rows as the 战报).
public struct SportBarRow<Accessory: View>: View {
    private let symbol: String
    private let name: Text
    private let count: Int
    private let unit: Text
    private let fraction: Double
    private let fill: Color
    private let track: Color
    private let accessory: Accessory
    @Environment(\.sceneTheme) private var theme

    /// - Parameters:
    ///   - fraction: against the most-counted row, 0 to 1; a row never draws its bar shorter
    ///     than round.
    ///   - fill: the circle's and the bar's colour.
    ///   - track: the bar's empty part.
    public init(
        symbol: String, name: Text, count: Int, unit: Text, fraction: Double, fill: Color, track: Color,
        @ViewBuilder accessory: () -> Accessory
    ) {
        (self.symbol, self.name, self.count, self.unit) = (symbol, name, count, unit)
        (self.fraction, self.fill, self.track) = (fraction, fill, track)
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: symbol)
                .font(.system(size: Self.glyph, weight: .semibold))
                .foregroundStyle(Color(role: .fgOnAccent, in: theme))
                .frame(width: Self.icon, height: Self.icon)
                .background(fill, in: Circle())
                .accessibilityHidden(true)
            name
                .typeStyle(TypeRamp.calloutEmphasis)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: Self.nameWidth, alignment: .leading)
            accessory
            Capsule()
                .fill(track)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(fill)
                            .frame(width: max(proxy.size.width * min(max(fraction, 0), 1), Self.bar))
                    }
                }
                .frame(height: Self.bar)
            HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
                Text(verbatim: "\(count)").typeStyle(TypeRamp.scoreInline).monospacedDigit()
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                unit.typeStyle(TypeRamp.caption)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
            }
            .frame(width: Self.countWidth, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private static var icon: Double { 28 }
    private static var glyph: Double { 14 }
    private static var nameWidth: Double { 72 }
    private static var bar: Double { 12 }
    private static var countWidth: Double { 44 }
}

extension SportBarRow where Accessory == EmptyView {
    /// A row without an accessory.
    public init(
        symbol: String, name: Text, count: Int, unit: Text, fraction: Double, fill: Color, track: Color
    ) {
        self.init(
            symbol: symbol, name: name, count: count, unit: unit, fraction: fraction, fill: fill, track: track
        ) { EmptyView() }
    }
}
#endif
