#if os(iOS)
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import RecapDomain
import SportsUI
import SwiftUI

/// 全队运动总结: the squad's 训练, the week's fun numbers on up to six cards (训练最多的一天,
/// 坚持运动最久, 互相加油, 一共训练了, 吃得健康, 请假条) and the mix of sports it trained. Nothing staged
/// but a quick pop-in.
struct SquadWeekPage: View {
    let week: RecapDomain.SquadWeek
    let page: PageContext
    @Environment(\.sceneTheme) private var theme
    /// Everyone's head, made once as the page appears (not in `init`: the page is made anew on
    /// every frame of its clock), so no card shows a blank one.
    @State private var heads: [MemberID: CharacterPlayer] = [:]

    var body: some View {
        // All the cards when they fit, fewer on a short phone.
        ViewThatFits(in: .vertical) {
            summary(cards: 6)
            summary(cards: 4)
            summary(cards: 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear(perform: makeHeads)
        .onChange(of: week, makeHeads)
    }

    private func summary(cards: Int) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            PageTitle(label: Text(copy: "全队", bundle: .module), title: Text(copy: "运动总结", bundle: .module))
            HStack(alignment: .lastTextBaseline, spacing: Space.s) {
                // The squad's 训练, several on one day each counting, as its goal counts them.
                Score(count: page.story.ending?.done ?? 0, size: .hero)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(copy: "次训练", bundle: .module).typeStyle(TypeRamp.headline)
                    Text(copy: "\(week.members.count) 人 · \(week.sports.count) 种运动", bundle: .module)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                }
            }
            .accessibilityElement(children: .combine)
            .padding(.horizontal, Space.l)
            VStack(alignment: .leading, spacing: Space.m) {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: Space.s), GridItem(.flexible(), spacing: Space.s)],
                    spacing: Space.s
                ) {
                    ForEach(Array(facts.prefix(cards).enumerated()), id: \.offset) { index, fact in
                        FactCard(
                            fact: fact, monday: page.story.week.monday, everyone: week.members.count,
                            nickname: nickname, people: people(fact), head: { heads[$0] }
                        )
                        .scaleEffect(0.9 + 0.1 * page.pop(Double(index) * 0.04, 0.32 + Double(index) * 0.04))
                        .opacity(page.ramp(Double(index) * 0.04, 0.12 + Double(index) * 0.04))
                    }
                }
                SportsCard(week: week, head: { heads[$0] })
            }
            .padding(.horizontal, Space.l)
        }
        // PageTitle keeps its own inset.
        .foregroundStyle(Color(role: .fgOnScene, in: theme))
    }

    private func makeHeads() {
        heads = Dictionary(
            week.members.compactMap { member in page.cast.player(of: member.member).map { (member.member, $0) } },
            uniquingKeysWith: { first, _ in first })
    }

    private func nickname(_ member: MemberID) -> String { page.cast[member]?.nickname ?? "" }

    /// Whose heads a card shows: who trained that day or that sport, and whose streak it was.
    private func people(_ fact: Fact) -> [MemberID] {
        switch fact {
        case .bestDay(let best): week.members(trainedOn: best.weekday)
        case .streak(_, _, let member?): [member]
        case .topSport(let top): week.members(training: [top.sport])
        default: []
        }
    }

    /// The week's fun numbers, up to six: a number the week doesn't have is left out, and
    /// without enough minutes logged the squad's top sport takes the time's place.
    private var facts: [Fact] {
        var facts: [Fact] = []
        if let best = week.bestDay { facts.append(.bestDay(best)) }
        if let streak = week.longestStreak {
            facts.append(.streak(days: streak.days, from: streak.from, member: streak.member))
        }
        if week.reactions > 0 { facts.append(.reactions(week.reactions)) }
        if let time = week.time {
            facts.append(
                .time(minutes: time.minutes, longest: time.longest.minutes, longestOn: .member(time.longest.member)))
        } else if let top = week.sports.first {
            facts.append(.topSport(top))
        }
        if let meals = page.story.meals, meals.healthy > 0 {
            facts.append(.meals(healthy: meals.healthy, cheat: meals.cheat))
        }
        if let disclaimers = week.disclaimers { facts.append(.disclaimers(disclaimers)) }
        return facts
    }
}

/// 项目: the squad's sports on a card, a row each for the top four with its symbol, who
/// trained it, a bar against the most-trained one and its days, and the rest together as 其他.
private struct SportsCard: View {
    let week: RecapDomain.SquadWeek
    let head: (MemberID) -> CharacterPlayer?
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        let sports = week.sports
        let most = max(sports.first?.days ?? 1, 1)
        let rest = sports.dropFirst(Self.named)
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(copy: "项目", bundle: .module)
                    .typeStyle(TypeRamp.label)
                    .foregroundStyle(Color(role: .fgAccent, in: theme))
                Spacer(minLength: Space.s)
                Text(copy: "\(sports.count) 种运动", bundle: .module)
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
            }
            ForEach(Array(sports.prefix(Self.named)), id: \.sport) { sport in
                SportRow(
                    symbol: sport.sport.symbol, name: sport.sport.cardName,
                    heads: week.members(training: [sport.sport]).map(head), days: sport.days,
                    fraction: Double(sport.days) / Double(most), isRest: false)
            }
            if !rest.isEmpty {
                SportRow(
                    symbol: "ellipsis", name: Text(copy: "其他 \(rest.count) 种", bundle: .module),
                    heads: week.members(training: Set(rest.map(\.sport))).map(head),
                    days: rest.reduce(0) { $0 + $1.days },
                    fraction: Double(rest.reduce(0) { $0 + $1.days }) / Double(most), isRest: true)
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

/// One sport on 项目: its symbol in a circle, its name, who trained it (two heads and
/// 「+N」), a bar and its days.
private struct SportRow: View {
    let symbol: String
    let name: Text
    let heads: [CharacterPlayer?]
    let days: Int
    /// Against the most-trained sport, 0 to 1 (其他 may pass it).
    let fraction: Double
    let isRest: Bool
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
            HeadStack(heads, size: Self.head, on: .bgCanvas, limit: Self.headLimit)
                .frame(
                    width: Self.head * Double(Self.headLimit + 1) - Space.xxs * Double(Self.headLimit),
                    alignment: .leading)
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
            HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
                Text(verbatim: "\(days)").typeStyle(TypeRamp.scoreInline).monospacedDigit()
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                Text(copy: "天", bundle: .module).typeStyle(TypeRamp.caption)
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
    private static let head: Double = 22
    /// Heads before 「+N」.
    private static let headLimit = 2
}

#endif
