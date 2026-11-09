#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import Foundation
import MeDomain
import SportsUI
import SwiftUI

// 外卡记录's tiles, in the page's order. Numbers count up in the order they stand on the page,
// and bars rise the same way: the weekdays first, then 最常练's tracks.

/// 训练时间: the hour the member trains at most (晚七点运动), what they alone are first at in the
/// squad, the member training beside the 24-hour clock, and the weekdays.
struct RecordsHero: View {
    let records: WildcardRecords
    let runner: CharacterPlayer?
    let still: Bool
    let intro: RecordsIntro
    @Environment(\.sceneTheme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        RecordsTile(topPadding: Self.topPadding, spacing: Space.s) {
            RecordsLabel(text: Text(copy: "训练时间", bundle: .module))
            if let hour = records.usualHour {
                RecordsHourTitle(hour: hour)
                    .typeStyle(TypeRamp.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if let firsts = records.squad?.firsts, !firsts.isEmpty {
                chips(firsts)
            }
            HStack(alignment: .bottom, spacing: Space.xxs) {
                RecordsFigure(player: runner, still: still)
                    .frame(width: Self.runner.width, height: Self.runner.height)
                    .padding(.leading, -Space.xs)
                Spacer(minLength: 0)
                RecordsClock(hours: records.hours, usual: records.usualHour, intro: intro)
                    .frame(width: Self.clock, height: Self.clock)
            }
            .padding(.top, Self.stageLift)
            weekdays
            HStack(alignment: .firstTextBaseline) {
                Text(copy: "每个周几练了几次", bundle: .module)
                    .foregroundStyle(Color(role: .fgOnBrandMuted, in: theme))
                    .typeStyle(TypeRamp.caption)
                Spacer(minLength: Space.xs)
                if let busiest = records.busiestWeekday {
                    let name = Self.weekdayName(busiest, locale: locale)
                    Text(copy: "\(name)最多", bundle: .module)
                        .typeStyle(TypeRamp.captionEmphasis)
                }
            }
            .lineLimit(1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("records.hero")
    }

    private func chips(_ firsts: [SquadStanding.First]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Self.chipGap) { chipRow(firsts) }
            VStack(alignment: .leading, spacing: Self.chipGap) { chipRow(firsts) }
        }
    }

    @ViewBuilder private func chipRow(_ firsts: [SquadStanding.First]) -> some View {
        ForEach(firsts, id: \.self) { first in
            chip(first)
                .typeStyle(TypeRamp.footnoteEmphasis)
                .foregroundStyle(Color(role: .bgBrand, in: theme))
                .lineLimit(1)
                .padding(.vertical, Space.xxs)
                .padding(.horizontal, Self.chipInset)
                .background(Color(role: .fgOnBrand, in: theme), in: .capsule)
        }
    }

    private func chip(_ first: SquadStanding.First) -> Text {
        switch first {
        case .latestTrainer: Text(copy: "小队里练得最晚", bundle: .module)
        case .earliestTrainer: Text(copy: "小队里练得最早", bundle: .module)
        case .mostDays: Text(copy: "小队里练得最多", bundle: .module)
        case .topSport:
            if let top = records.sports.first {
                Text(copy: "小队里\(top.activity.name)最多", bundle: .module)
            } else {
                Text(copy: "小队里练得最多", bundle: .module)
            }
        }
    }

    /// Seven bars, Monday first, as tall as each weekday was trained; the busiest in white.
    private var weekdays: some View {
        let most = max(records.weekdays.max() ?? 0, 1)
        return HStack(spacing: Self.barGap) {
            ForEach(Array(records.weekdays.enumerated()), id: \.offset) { index, days in
                let isTop = days == most && days > 0
                VStack(spacing: Self.barGap) {
                    Capsule()
                        .fill(Color(role: .fgOnBrand, in: theme).opacity(isTop ? 1 : Self.barShade))
                        .frame(
                            width: Self.barWidth,
                            height: (Self.barFloor + Double(days) / Double(most) * Self.barRise) * intro.bar(index)
                        )
                        .frame(height: Self.barFloor + Self.barRise, alignment: .bottom)
                    Text(verbatim: Self.weekdayLetter(index, locale: locale))
                        .typeStyle(isTop ? TypeRamp.captionEmphasis : TypeRamp.caption)
                        .foregroundStyle(Color(role: isTop ? .fgOnBrand : .fgOnBrandMuted, in: theme))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(copy: "每个周几练了几次", bundle: .module))
        .accessibilityValue(
            Text(
                verbatim: records.weekdays.enumerated()
                    .map { "\(Self.weekdayName($0.offset, locale: locale)) \($0.element)" }
                    .joined(separator: ", ")))
    }

    /// Monday first: 一 … 日 / M … S.
    static func weekdayLetter(_ index: Int, locale: Locale) -> String {
        weekday(index, locale: locale, \.veryShortStandaloneWeekdaySymbols)
    }

    /// Monday first: 周一 … 周日 / Mon … Sun.
    static func weekdayName(_ index: Int, locale: Locale) -> String {
        weekday(index, locale: locale, \.shortStandaloneWeekdaySymbols)
    }

    private static func weekday(_ index: Int, locale: Locale, _ symbols: KeyPath<Calendar, [String]>) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let names = calendar[keyPath: symbols]
        // The calendar's week starts on Sunday.
        return names.indices.contains((index + 1) % 7) ? names[(index + 1) % 7] : ""
    }

    /// The hero's top padding: a little more than a tile's.
    private static let topPadding = Space.cardPadding + Space.xxs
    private static let runner = CGSize(width: 132, height: 176)
    private static let clock = 186.0
    private static let stageLift = 2.0
    private static let chipGap = 6.0
    private static let chipInset = 10.0
    private static let barGap = 6.0
    private static let barWidth = 14.0
    private static let barFloor = 8.0
    private static let barRise = 32.0
    private static let barShade = 0.22
}

/// The hour the member trains at most, as a name for them: 晚七点运动 / 7 PM regular.
struct RecordsHourTitle: View {
    let hour: Int

    var body: some View {
        switch hour {
        case 0: Text(copy: "半夜十二点运动", bundle: .module)
        case 1: Text(copy: "凌晨一点运动", bundle: .module)
        case 2: Text(copy: "凌晨两点运动", bundle: .module)
        case 3: Text(copy: "凌晨三点运动", bundle: .module)
        case 4: Text(copy: "凌晨四点运动", bundle: .module)
        case 5: Text(copy: "早五点运动", bundle: .module)
        case 6: Text(copy: "早六点运动", bundle: .module)
        case 7: Text(copy: "早七点运动", bundle: .module)
        case 8: Text(copy: "早八点运动", bundle: .module)
        case 9: Text(copy: "早九点运动", bundle: .module)
        case 10: Text(copy: "早十点运动", bundle: .module)
        case 11: Text(copy: "上午十一点运动", bundle: .module)
        case 12: Text(copy: "中午十二点运动", bundle: .module)
        case 13: Text(copy: "下午一点运动", bundle: .module)
        case 14: Text(copy: "下午两点运动", bundle: .module)
        case 15: Text(copy: "下午三点运动", bundle: .module)
        case 16: Text(copy: "下午四点运动", bundle: .module)
        case 17: Text(copy: "下午五点运动", bundle: .module)
        case 18: Text(copy: "晚六点运动", bundle: .module)
        case 19: Text(copy: "晚七点运动", bundle: .module)
        case 20: Text(copy: "晚八点运动", bundle: .module)
        case 21: Text(copy: "晚九点运动", bundle: .module)
        case 22: Text(copy: "晚十点运动", bundle: .module)
        default: Text(copy: "晚十一点运动", bundle: .module)
        }
    }
}

/// 24 hours round a dial, midnight at the top: a hand for each hour a 练了 was posted in, as long
/// as how often, the longest white with a dot at its tip, and the usual hour in the middle.
struct RecordsClock: View {
    let hours: [Int]
    /// The hour the member trains at most, whose hand is white.
    let usual: Int?
    let intro: RecordsIntro
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        let most = hours.max() ?? 0
        Canvas { context, size in
            context.scaleBy(x: size.width / Self.grid, y: size.height / Self.grid)
            let white = Color(role: .fgOnBrand, in: theme)
            let center = CGPoint(x: Self.grid / 2, y: Self.grid / 2)
            func point(_ hour: Int, _ radius: Double) -> CGPoint {
                let angle = (Double(hour) * 15 - 90) * .pi / 180
                return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            }
            context.fill(
                Path(ellipseIn: CGRect(x: 1, y: 1, width: Self.grid - 2, height: Self.grid - 2)),
                with: .color(white.opacity(0.06)))
            for hour in 0..<24 where hour % 6 != 0 {
                let dot = point(hour, 91)
                context.fill(
                    Path(ellipseIn: CGRect(x: dot.x - 1.2, y: dot.y - 1.2, width: 2.4, height: 2.4)),
                    with: .color(white.opacity(0.35)))
            }
            for (hour, name) in Self.quarters {
                let label = context.resolve(
                    name.font(.wildcard(TypeRamp.caption)).foregroundStyle(white.opacity(0.55)))
                // A longer word (6 PM) slides in rather than past the dial's edge.
                let half = label.measure(in: CGSize(width: Self.grid, height: Self.grid)).width / 2 + 4
                var spot = point(hour, 89)
                spot.x = min(max(spot.x, half), Self.grid - half)
                context.draw(label, at: spot, anchor: .center)
            }
            for hour in hours.indices where hours[hour] > 0 && most > 0 {
                let isTop = hour == usual
                let grown =
                    Self.inner + (Self.outer - Self.inner) * Double(hours[hour]) / Double(most) * intro.hand(hour)
                guard grown > Self.inner + 0.5 else { continue }
                var hand = Path()
                hand.move(to: point(hour, Self.inner))
                hand.addLine(to: point(hour, grown))
                context.stroke(
                    hand, with: .color(isTop ? white : white.opacity(0.5)),
                    style: StrokeStyle(lineWidth: isTop ? 8 : 6, lineCap: .round))
                if isTop {
                    let tip = point(hour, grown + 7)
                    context.fill(
                        Path(ellipseIn: CGRect(x: tip.x - 5, y: tip.y - 5, width: 10, height: 10)), with: .color(white))
                }
            }
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - 24, y: center.y - 24, width: 48, height: 48)),
                with: .color(Color(role: .bgBrand, in: theme)))
            if let usual {
                let number = Text(verbatim: "\(usual)").font(.wildcard(TypeRamp.scoreInline)).foregroundStyle(white)
                context.draw(
                    Text(copy: "\(number)点", bundle: .module)
                        .font(.wildcard(TypeRamp.caption))
                        .foregroundStyle(white.opacity(0.7)),
                    at: CGPoint(x: center.x, y: center.y + 1), anchor: .center)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(copy: "每个钟点练了几次", bundle: .module))
        .accessibilityValue(
            Text(
                verbatim: hours.indices.filter { hours[$0] > 0 }.map { "\($0):00 \(hours[$0])" }
                    .joined(separator: ", ")))
    }

    /// The dial's grid, in points before it is scaled to the frame.
    private static let grid = 200.0
    /// Where the hands start and how far the longest reaches, on the grid.
    private static let inner = 30.0
    private static let outer = 66.0
    private static var quarters: [(Int, Text)] {
        [
            (0, Text(copy: "半夜", bundle: .module)), (6, Text(copy: "早上", bundle: .module)),
            (12, Text(copy: "中午", bundle: .module)), (18, Text(copy: "晚上", bundle: .module)),
        ]
    }
}
#endif
