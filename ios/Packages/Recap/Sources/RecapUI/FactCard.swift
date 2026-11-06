#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import RecapDomain
import SportsUI
import SwiftUI

/// One of the week's fun numbers.
enum Fact {
    case bestDay(RecapDomain.SquadWeek.BestDay)
    /// Days in a row from a weekday (0 for Monday), and whose run it was on the squad's page.
    case streak(days: Int, from: Int, member: MemberID?)
    case reactions(Int)
    /// 收到加油: the reactions on the reader's own posts.
    case cheers(Int)
    /// The minutes logged and the longest day's, with whose or which day it was.
    case time(minutes: Int, longest: Int, longestOn: Longest)
    case topSport(RecapDomain.SquadWeek.SportDays)
    case meals(healthy: Int, cheat: Int)
    case disclaimers(RecapDomain.SquadWeek.Disclaimers)

    /// Who logged the longest day on the squad's page; on 你的一周, which day it was.
    enum Longest {
        case member(MemberID)
        case day(Int)
    }
}

/// A fun number on its card: what it is in the accent, the number big, and a line under it.
struct FactCard: View {
    let fact: Fact
    let monday: LocalDay
    /// How many are in the squad, to say when everyone trained the same day.
    let everyone: Int
    let nickname: (MemberID) -> String
    /// On the white ground (你的一周) the card is mist; on the scene it is see-through white.
    var onGround = false
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
            onGround ? Color(role: .bgSubtle, in: theme) : Color(role: .bgCanvas, in: theme).opacity(0.6),
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private var label: Text {
        switch fact {
        case .bestDay: Text("训练最多的一天", bundle: .module)
        case .streak: Text("坚持运动最久", bundle: .module)
        case .reactions: Text("互相加油", bundle: .module)
        case .cheers: Text("收到加油", bundle: .module)
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
        case .streak(let days, _, _):
            Number(count: days, unit: Text("天", bundle: .module))
        case .reactions(let count), .cheers(let count):
            Number(count: count, unit: nil)
        case .time(let minutes, _, _) where minutes >= 60:
            Number(count: Int((Double(minutes) / 60).rounded()), unit: Text("小时", bundle: .module))
        case .time(let minutes, _, _):
            Number(count: minutes, unit: Text("分钟", bundle: .module))
        case .topSport(let top):
            top.sport.cardName.typeStyle(TypeRamp.title)
        case .meals(let healthy, _):
            Number(count: healthy, unit: Text("顿", bundle: .module))
        case .disclaimers(let disclaimers):
            Number(count: disclaimers.days, unit: Text("张", bundle: .module))
        }
    }

    /// Who trained on the squad's best day: everyone, or how many.
    private func bestDayNote(members: Int) -> Text {
        if members == everyone { return Text("全员都训练了", bundle: .module) }
        return Text("\(members) 人训练了", bundle: .module)
    }

    private var note: Text {
        switch fact {
        case .bestDay(let best):
            bestDayNote(members: best.members)
        case .streak(let days, let from, let member):
            streakNote(from: from, through: from + days - 1, by: member)
        case .reactions, .cheers:
            Text("个回应", bundle: .module)
        case .time(_, let longest, let longestOn):
            longestNote(longest, on: longestOn)
        case .topSport(let top):
            Text("\(top.days) 天", bundle: .module)
        case .meals(_, let cheat):
            Text("坦白放纵 \(cheat) 顿", bundle: .module)
        case .disclaimers(let disclaimers):
            mostNote(disclaimers.most)
        }
    }

    /// 「最会请假 胖橘」.
    private func mostNote(_ member: MemberID) -> Text {
        let who = nickname(member)
        return Text("最会请假 \(who)", bundle: .module)
    }

    /// 「丸子 周二到周六」 on the squad's page, 「周三到周四」 on 你的一周.
    private func streakNote(from: Int, through: Int, by member: MemberID?) -> Text {
        let first = weekdayName(from)
        let last = weekdayName(through)
        guard let member else { return Text("\(first)到\(last)", bundle: .module) }
        let who = nickname(member)
        return Text("\(who) \(first)到\(last)", bundle: .module)
    }

    /// 「最久一天 阿凯 1小时35分钟」, or 「最久一天 周四 1小时20分钟」 on 你的一周.
    private func longestNote(_ minutes: Int, on longest: Fact.Longest) -> Text {
        let when =
            switch longest {
            case .member(let member): nickname(member)
            case .day(let index): weekdayName(index)
            }
        let span = duration(minutes)
        return Text("最久一天 \(when) \(span)", bundle: .module)
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

#endif
