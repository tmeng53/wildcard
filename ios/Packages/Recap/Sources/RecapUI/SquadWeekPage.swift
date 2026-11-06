#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import RecapDomain
import SportsUI
import SwiftUI

/// 全队运动总结: the squad's days trained, the week's fun numbers on up to six cards (训练最多的一天,
/// 坚持运动最久, 互相加油, 一共训练了, 吃得健康, 请假条) and the mix of sports it trained. Nothing staged
/// but a quick pop-in.
struct SquadWeekPage: View {
    let week: SquadWeek
    let page: PageContext
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        // All the cards when they fit, fewer on a short phone.
        ViewThatFits(in: .vertical) {
            summary(cards: 6)
            summary(cards: 4)
            summary(cards: 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func summary(cards: Int) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            PageTitle(label: Text("全队", bundle: .module), title: Text("运动总结", bundle: .module))
            HStack(alignment: .lastTextBaseline, spacing: Space.s) {
                Score(count: week.trainedDays, size: .hero)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("天训练", bundle: .module).typeStyle(TypeRamp.headline)
                    Text("\(week.members.count) 人 · \(week.sports.count) 种运动", bundle: .module)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                }
            }
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: Space.m) {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: Space.s), GridItem(.flexible(), spacing: Space.s)],
                    spacing: Space.s
                ) {
                    ForEach(Array(facts.prefix(cards).enumerated()), id: \.offset) { index, fact in
                        FactCard(
                            fact: fact, monday: page.story.week.monday, everyone: week.members.count,
                            nickname: nickname
                        )
                        .scaleEffect(0.9 + 0.1 * page.pop(Double(index) * 0.04, 0.32 + Double(index) * 0.04))
                        .opacity(page.ramp(Double(index) * 0.04, 0.12 + Double(index) * 0.04))
                    }
                }
                SportsCard(sports: week.sports)
            }
        }
        .padding(.horizontal, Space.l)
        .foregroundStyle(Color(role: .fgOnScene, in: theme))
    }

    private func nickname(_ member: MemberID) -> String { page.cast[member]?.nickname ?? "" }

    /// The week's fun numbers, up to six: a number the week doesn't have is left out, and
    /// without enough minutes logged the squad's top sport takes the time's place.
    private var facts: [Fact] {
        var facts: [Fact] = []
        if let best = week.bestDay { facts.append(.bestDay(best)) }
        if let streak = week.longestStreak { facts.append(.streak(streak)) }
        if week.reactions > 0 { facts.append(.reactions(week.reactions)) }
        if let time = week.time {
            facts.append(.time(time))
        } else if let top = week.sports.first {
            facts.append(.topSport(top))
        }
        if let meals = page.story.meals, meals.healthy > 0 { facts.append(.meals(meals)) }
        if let disclaimers = week.disclaimers { facts.append(.disclaimers(disclaimers)) }
        return facts
    }
}

/// One of the week's fun numbers.
private enum Fact {
    case bestDay(SquadWeek.BestDay)
    case streak(SquadWeek.Streak)
    case reactions(Int)
    case time(SquadWeek.TrainingTime)
    case topSport(SquadWeek.SportDays)
    case meals(Meals)
    case disclaimers(SquadWeek.Disclaimers)
}

/// A fun number on its card: what it is in the accent, the number big, and a line under it.
private struct FactCard: View {
    let fact: Fact
    let monday: LocalDay
    /// How many are in the squad, to say when everyone trained the same day.
    let everyone: Int
    let nickname: (MemberID) -> String
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            label
                .typeStyle(TypeRamp.label)
                .foregroundStyle(Color(role: .fgAccent, in: theme))
            value
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            note
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .background(
            Color(role: .bgCanvas, in: theme).opacity(0.6),
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private var label: Text {
        switch fact {
        case .bestDay: Text("训练最多的一天", bundle: .module)
        case .streak: Text("坚持运动最久", bundle: .module)
        case .reactions: Text("互相加油", bundle: .module)
        case .time: Text("一共训练了", bundle: .module)
        case .topSport: Text("练得最多", bundle: .module)
        case .meals: Text("吃得健康", bundle: .module)
        case .disclaimers: Text("请假条", bundle: .module)
        }
    }

    @ViewBuilder private var value: some View {
        switch fact {
        case .bestDay(let best):
            Text(verbatim: weekdayName(best.weekday)).typeStyle(TypeRamp.title)
        case .streak(let streak):
            Number(count: streak.days, unit: Text("天", bundle: .module))
        case .reactions(let count):
            Number(count: count, unit: nil)
        case .time(let time) where time.minutes >= 60:
            Number(count: Int((Double(time.minutes) / 60).rounded()), unit: Text("小时", bundle: .module))
        case .time(let time):
            Number(count: time.minutes, unit: Text("分钟", bundle: .module))
        case .topSport(let top):
            top.sport.cardName.typeStyle(TypeRamp.title)
        case .meals(let meals):
            Number(count: meals.healthy, unit: Text("顿", bundle: .module))
        case .disclaimers(let disclaimers):
            Number(count: disclaimers.days, unit: Text("张", bundle: .module))
        }
    }

    private var note: Text {
        switch fact {
        case .bestDay(let best):
            best.members == everyone
                ? Text("全员都训练了", bundle: .module) : Text("\(best.members) 人训练了", bundle: .module)
        case .streak(let streak):
            Text(
                "\(nickname(streak.member)) \(weekdayName(streak.from))到\(weekdayName(streak.through))",
                bundle: .module)
        case .reactions:
            Text("个回应", bundle: .module)
        case .time(let time):
            longestNote(time.longest)
        case .topSport(let top):
            Text("\(top.days) 天", bundle: .module)
        case .meals(let meals):
            Text("坦白放纵 \(meals.cheat) 顿", bundle: .module)
        case .disclaimers(let disclaimers):
            mostNote(disclaimers.most)
        }
    }

    /// 「最会请假 胖橘」.
    private func mostNote(_ member: MemberID) -> Text {
        let who = nickname(member)
        return Text("最会请假 \(who)", bundle: .module)
    }

    /// 「最久一天 阿凯 1小时35分钟」.
    private func longestNote(_ longest: SquadWeek.LongestDay) -> Text {
        let who = nickname(longest.member)
        let span = duration(longest.minutes)
        return Text("最久一天 \(who) \(span)", bundle: .module)
    }

    /// 「周三」: the week's day, 0 for Monday, in the app's language.
    private func weekdayName(_ index: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let start = calendar.date(from: DateComponents(year: monday.year, month: monday.month, day: monday.day))
        let date = start.flatMap { calendar.date(byAdding: .day, value: index, to: $0) } ?? .distantPast
        let style = Date.FormatStyle(timeZone: calendar.timeZone).weekday(.abbreviated)
        return date.formatted(style.locale(AppLanguage.current.locale))
    }

    /// 「1小时30分钟」, in the app's language.
    private func duration(_ minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(
            .units(allowed: [.hours, .minutes], width: .abbreviated).locale(AppLanguage.current.locale))
    }
}

/// A count in the scoreboard face with its unit small beside it.
private struct Number: View {
    let count: Int
    let unit: Text?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
            Text(verbatim: "\(count)").typeStyle(TypeRamp.scoreCard).monospacedDigit()
            unit?.typeStyle(TypeRamp.footnoteEmphasis)
        }
    }
}

/// 全队练了什么: the squad's sports on a card, a row each for the top four with its symbol, a
/// bar against the most-trained one and its days, and the rest together as 其他.
private struct SportsCard: View {
    let sports: [SquadWeek.SportDays]
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        let most = max(sports.first?.days ?? 1, 1)
        let rest = sports.dropFirst(Self.named)
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("全队练了什么", bundle: .module)
                    .typeStyle(TypeRamp.label)
                    .foregroundStyle(Color(role: .fgAccent, in: theme))
                Spacer(minLength: Space.s)
                Text("\(sports.count) 种运动", bundle: .module)
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
            }
            ForEach(Array(sports.prefix(Self.named).enumerated()), id: \.element.sport) { index, sport in
                SportRow(
                    symbol: sport.sport.symbol, name: sport.sport.cardName, days: sport.days,
                    fraction: Double(sport.days) / Double(most), isRest: false, start: Double(index) * 0.04)
            }
            if !rest.isEmpty {
                SportRow(
                    symbol: "ellipsis", name: Text("其他 \(rest.count) 种", bundle: .module),
                    days: rest.reduce(0) { $0 + $1.days },
                    fraction: Double(rest.reduce(0) { $0 + $1.days }) / Double(most), isRest: true,
                    start: Double(Self.named) * 0.04)
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .background(
            Color(role: .bgCanvas, in: theme).opacity(0.6),
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
    }

    /// Sports with a row of their own; the rest go together.
    private static let named = 4
}

/// One sport on 全队练了什么: its symbol in a circle, its name, a bar and its days.
private struct SportRow: View {
    let symbol: String
    let name: Text
    let days: Int
    /// Against the most-trained sport, 0 to 1 (其他 may pass it).
    let fraction: Double
    let isRest: Bool
    let start: Double
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        let fill = Color(role: isRest ? .fgMuted : .bgAccent, in: theme)
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
            Capsule()
                .fill(Color(role: .bgCanvas, in: theme).opacity(0.8))
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(fill)
                            .frame(width: max(proxy.size.width * min(fraction, 1), Self.bar))
                    }
                }
                .frame(height: Self.bar)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(verbatim: "\(days)").typeStyle(TypeRamp.scoreInline).monospacedDigit()
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                Text("天", bundle: .module).typeStyle(TypeRamp.caption)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
            }
            .frame(width: Self.daysWidth, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private static let icon: Double = 28
    private static let glyph: Double = 14
    private static let nameWidth: Double = 72
    private static let bar: Double = 12
    private static let daysWidth: Double = 44
}

#endif
