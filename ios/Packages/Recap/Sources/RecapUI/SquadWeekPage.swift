#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import RecapDomain
import SportsUI
import SwiftUI

/// 全队运动总结: the squad's days trained, the week's fun numbers on up to six cards (训练最多的一天,
/// 坚持运动最久, 互相加油, 一共训练了, 吃得健康, 请假条) and the mix of sports it trained; everyone standing on the
/// ground's edge doing their own top sport, smaller and closer in a big squad. Nothing staged but a quick pop-in.
struct SquadWeekPage: View {
    let week: SquadWeek
    let page: PageContext
    @Environment(\.sceneTheme) private var theme

    /// Those the page can draw, in the order they joined, at most a row's worth.
    private var lineup: [SquadWeek.Member] {
        Array(week.members.filter { page.cast[$0.member] != nil }.prefix(Self.most))
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let floor = proxy.size.height - StoryLayout.groundSquadWeek
            let lineup = lineup
            let spacing = (width - 2 * Space.l) / Double(max(lineup.count, 1))
            let scale = min(Self.scale, spacing / Self.figureWidth)
            ZStack(alignment: .topLeading) {
                Ground(height: StoryLayout.groundSquadWeek)
                ForEach(Array(lineup.enumerated()), id: \.element.member) { index, member in
                    let spot = Space.l + spacing * (Double(index) + 0.5)
                    page.character(
                        member.member,
                        act: Act(
                            clip: member.topSport.weekClip, start: 0.3 + Double(index) * 0.06,
                            seed: Double(index) * 0.41)
                    )
                    .standing(feetAt: CGPoint(x: spot, y: floor), scale: scale)
                    // Neighbours overlap in a big squad: every other one stands in front.
                    .zIndex(index.isMultiple(of: 2) ? 1 : 0)
                }
            }
        }
        .overlay(alignment: .top) {
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
                        ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                            FactCard(fact: fact, monday: page.story.week.monday, nickname: nickname)
                                .scaleEffect(0.9 + 0.1 * page.pop(Double(index) * 0.04, 0.32 + Double(index) * 0.04))
                                .opacity(page.ramp(Double(index) * 0.04, 0.12 + Double(index) * 0.04))
                        }
                    }
                    SportsMix(sports: week.sports)
                }
            }
            .padding(.horizontal, Space.l)
            .foregroundStyle(Color(role: .fgOnScene, in: theme))
        }
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
        if let meals = page.story.meals, meals.healthy + meals.cheat > 0 { facts.append(.meals(meals)) }
        if let disclaimers = week.disclaimers { facts.append(.disclaimers(disclaimers)) }
        return facts
    }

    /// The most the ground holds side by side.
    private static let most = 8
    private static let scale = 0.42
    /// How much room a character needs at scale 1, for fitting a big squad (neighbours may
    /// overlap a little).
    private static let figureWidth = 125.0
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
            Text("\(best.members) 人都训练了", bundle: .module)
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

/// The squad's sports as one bar split by days, the top three in the accent from strong to
/// light and the rest together as 其他, with a legend of each and its days under it.
private struct SportsMix: View {
    let sports: [SquadWeek.SportDays]
    @Environment(\.sceneTheme) private var theme

    private struct Part: Identifiable {
        let id: Int
        let name: Text
        let days: Int
    }

    private var parts: [Part] {
        var parts = sports.prefix(Self.named).enumerated().map { Part(id: $0, name: $1.sport.cardName, days: $1.days) }
        let rest = sports.dropFirst(Self.named).reduce(0) { $0 + $1.days }
        if rest > 0 { parts.append(Part(id: Self.named, name: Text("其他", bundle: .module), days: rest)) }
        return parts
    }

    var body: some View {
        let parts = parts
        let total = max(parts.reduce(0) { $0 + $1.days }, 1)
        VStack(alignment: .leading, spacing: Space.xs) {
            GeometryReader { proxy in
                let room = proxy.size.width - Self.gap * Double(max(parts.count - 1, 0))
                HStack(spacing: Self.gap) {
                    ForEach(parts) { part in
                        Rectangle()
                            .fill(color(part.id))
                            .frame(width: room * Double(part.days) / Double(total))
                    }
                }
            }
            .frame(height: Self.height)
            .clipShape(Capsule())
            HStack(spacing: Space.s) {
                ForEach(parts) { part in
                    HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
                        Circle().fill(color(part.id)).frame(width: Self.dot, height: Self.dot)
                        part.name.typeStyle(TypeRamp.caption)
                        Text(verbatim: "\(part.days)").typeStyle(TypeRamp.scoreSmall).monospacedDigit()
                        Text("天", bundle: .module).typeStyle(TypeRamp.caption)
                    }
                    .lineLimit(1)
                    .accessibilityElement(children: .combine)
                }
            }
            .minimumScaleFactor(0.8)
        }
    }

    /// The top sports in the accent, each lighter than the last; 其他 in the ground's white.
    private func color(_ index: Int) -> Color {
        index < Self.named
            ? Color(role: .bgAccent, in: theme).opacity([1, 0.6, 0.35][index])
            : Color(role: .bgCanvas, in: theme).opacity(0.75)
    }

    /// Sports named on their own; the rest go together.
    private static let named = 3
    private static let height: Double = 16
    private static let gap: Double = 3
    private static let dot: Double = 8
}

/// 「5 天」: the count in the scoreboard face, the unit small beside it.
private struct DaysCount: View {
    let days: Int
    var style = TypeRamp.scoreInline

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(verbatim: "\(days)").typeStyle(style).monospacedDigit()
            Text("天", bundle: .module).typeStyle(TypeRamp.caption)
        }
    }
}
#endif
