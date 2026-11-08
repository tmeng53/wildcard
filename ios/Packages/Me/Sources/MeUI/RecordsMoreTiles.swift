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

// 外卡记录's tiles under 训练时间: the streaks, 最常练, the totals and 和小队.

/// A streak (最长连续训练, 健康餐连续): its days, a logo ticket a day (four and +N past five), and
/// from when to when.
struct StreakTile: View {
    let label: Text
    let streak: WildcardRecords.Streak?
    let today: LocalDay
    /// Which streak tile it is, for when its tickets punch in.
    let order: Int
    let intro: RecordsIntro
    @Environment(\.sceneTheme) private var theme

    /// At most five tickets show; past five, four and +N.
    static let mostTickets = 5

    static func ticketsShown(_ days: Int) -> Int { days > mostTickets ? mostTickets - 1 : days }

    var body: some View {
        let days = streak?.days ?? 0
        RecordsTile {
            RecordsLabel(text: label)
            RecordsNumber(value: days, unit: Text("天", bundle: .module), progress: intro.number(order))
            HStack(spacing: Self.ticketGap) {
                ForEach(0..<Self.ticketsShown(days), id: \.self) { index in
                    let size = intro.ticket(tile: order, index: index)
                    LogoTicket()
                        .scaleEffect(size, anchor: .bottom)
                        .opacity(min(1, size * 2))
                }
                if days > Self.mostTickets {
                    Text(verbatim: "+\(days - Self.ticketsShown(days))")
                        .typeStyle(TypeRamp.scoreCaption)
                        .padding(.horizontal, Space.xs)
                        .frame(height: Self.moreHeight)
                        .background(
                            Color(role: .fgOnBrand, in: theme).opacity(0.16),
                            in: .rect(cornerRadius: Self.moreHeight / 2))
                }
            }
            .frame(height: LogoTicket.size.height)
            .accessibilityHidden(true)
            if let streak {
                RecordsDays(streak: streak, today: today)
                    .typeStyle(TypeRamp.caption)
                    .foregroundStyle(Color(role: .fgOnBrandMuted, in: theme))
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private static let ticketGap = 5.0
    private static let moreHeight = 24.0
}

/// 10.20 – 10.25, or 10.6 – 今天 when it runs to today.
struct RecordsDays: View {
    let streak: WildcardRecords.Streak
    let today: LocalDay

    var body: some View {
        let (month, day) = (streak.first.month, streak.first.day)
        let first = Text("\(month).\(day)", bundle: .module)
        let last =
            streak.last == today
            ? Text("今天", bundle: .module) : Text("\(streak.last.month).\(streak.last.day)", bundle: .module)
        Text("\(first) – \(last)", bundle: .module)
    }
}

/// 最常练: the top three sports by days, each with its icon and a bar against the first, and how
/// many sports the member trained in all.
struct TopSportsTile: View {
    let records: WildcardRecords
    let intro: RecordsIntro
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        let most = max(records.sports.first?.days ?? 0, 1)
        RecordsTile {
            HStack(alignment: .firstTextBaseline) {
                RecordsLabel(text: Text("最常练", bundle: .module))
                Spacer(minLength: Space.xs)
                Text("\(records.sportCount) 种运动", bundle: .module)
                    .typeStyle(TypeRamp.caption)
                    .foregroundStyle(Color(role: .fgOnBrandMuted, in: theme))
                    .lineLimit(1)
            }
            ForEach(Array(records.sports.enumerated()), id: \.offset) { index, sport in
                HStack(spacing: Space.xs) {
                    Image(systemName: sport.activity.symbol)
                        .font(.system(size: Self.iconSize, weight: .medium))
                        .frame(width: Self.iconCircle, height: Self.iconCircle)
                        .background(Color(role: .fgOnBrand, in: theme).opacity(0.12), in: .circle)
                        .accessibilityHidden(true)
                    sport.activity.cardName
                        .typeStyle(TypeRamp.callout)
                        .lineLimit(1)
                        .frame(width: Self.nameWidth, alignment: .leading)
                    Capsule()
                        .fill(Color(role: .fgOnBrand, in: theme).opacity(0.1))
                        .frame(height: Self.track)
                        .overlay(alignment: .leading) {
                            GeometryReader { space in
                                Capsule()
                                    .fill(Color(role: .fgOnBrand, in: theme))
                                    .frame(
                                        width: space.size.width * Double(sport.days) / Double(most)
                                            * intro.bar(7 + index))
                            }
                        }
                    HStack(alignment: .firstTextBaseline, spacing: Self.unitGap) {
                        Text(verbatim: "\(Int((Double(sport.days) * intro.number(2 + index)).rounded()))")
                            .typeStyle(TypeRamp.scoreSmall)
                            .monospacedDigit()
                        Text("天", bundle: .module)
                            .typeStyle(TypeRamp.caption)
                            .foregroundStyle(Color(role: .fgOnBrandMuted, in: theme))
                    }
                    .lineLimit(1)
                    .frame(width: Self.countWidth, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(sport.activity.name)
                .accessibilityValue(Text("\(sport.days) 天", bundle: .module))
            }
        }
    }

    private static let iconCircle = 30.0
    private static let iconSize = 15.0
    private static let nameWidth = 64.0
    private static let track = 8.0
    private static let countWidth = 44.0
    private static let unitGap = 2.0
}

/// 一共训练 N 天 · 一共 N 小时 · 最长一次 N 分钟, in three columns.
struct TotalsTile: View {
    let records: WildcardRecords
    let intro: RecordsIntro
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        RecordsTile {
            HStack(alignment: .top, spacing: 0) {
                column(Text("一共训练", bundle: .module), records.trainedDays, Text("天", bundle: .module), order: 5)
                divider
                column(Text("一共", bundle: .module), records.hoursTrained, Text("小时", bundle: .module), order: 6)
                divider
                if let longest = records.longestMinutes {
                    column(Text("最长一次", bundle: .module), longest, Text("分钟", bundle: .module), order: 7)
                } else {
                    VStack(alignment: .leading, spacing: Self.gap) {
                        RecordsLabel(text: Text("最长一次", bundle: .module))
                        Text(verbatim: "–").typeStyle(TypeRamp.scoreCard)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func column(_ label: Text, _ value: Int, _ unit: Text, order: Int) -> some View {
        VStack(alignment: .leading, spacing: Self.gap) {
            RecordsLabel(text: label)
            RecordsNumber(value: value, unit: unit, progress: intro.number(order))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(role: .fgOnBrand, in: theme).opacity(0.12))
            .frame(width: Sizing.hairline)
            .padding(.trailing, Self.inset)
    }

    private static let gap = 6.0
    private static let inset = 14.0
}

/// 和小队: the best partner, the two of them bumping fists, then the cheers received and given.
struct SquadRecordsSection: View {
    let squad: SquadStanding
    let cast: RecordsCast
    let still: Bool
    let intro: RecordsIntro
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        Text("和小队", bundle: .module)
            .typeStyle(TypeRamp.title)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Space.m)
            .accessibilityAddTraits(.isHeader)
        if let partner = squad.partner {
            RecordsTile {
                RecordsLabel(text: Text("最佳搭档", bundle: .module))
                HStack(alignment: .bottom, spacing: Space.xs) {
                    ZStack(alignment: .topLeading) {
                        RecordsFigure(player: cast.member, still: still)
                            .frame(width: Self.figure.width, height: Self.figure.height)
                            .offset(x: Self.meAt)
                        RecordsFigure(player: cast.partner, still: still)
                            .frame(width: Self.figure.width, height: Self.figure.height)
                            // Facing the member, so their fists meet.
                            .scaleEffect(x: -1)
                            .offset(x: Self.partnerAt)
                    }
                    .frame(width: Self.duo.width, height: Self.duo.height, alignment: .topLeading)
                    // The characters' canvases have room around them: they reach into the padding.
                    .padding(.top, Self.duoReach.top)
                    .padding(.leading, Self.duoReach.leading)
                    .padding(.bottom, Self.duoReach.bottom)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Self.nameGap) {
                        RecordsMateName(mate: partner.mate)
                            .typeStyle(TypeRamp.title)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        let count = bold(partner.count)
                        Text("同一天练了 \(count) 次", bundle: .module)
                            .typeStyle(TypeRamp.caption)
                            .foregroundStyle(Color(role: .fgOnBrandMuted, in: theme))
                            .lineLimit(1)
                    }
                    .padding(.bottom, Self.nameLift)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("records.partner")
        }
        HStack(alignment: .top, spacing: Space.cardGap) {
            CheersTile(
                label: Text("收到加油", bundle: .module), cheers: squad.cheersReceived, received: true, order: 8,
                intro: intro, cast: cast)
            CheersTile(
                label: Text("送出加油", bundle: .module), cheers: squad.cheersGiven, received: false, order: 9,
                intro: intro, cast: cast)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A count picked out in white inside a muted line.
    private func bold(_ count: Int) -> Text {
        Text(verbatim: "\(count)").foregroundStyle(Color(role: .fgOnBrand, in: theme)).bold()
    }

    /// The two characters, each three-quarters of a character's canvas, side by side.
    private static let duo = CGSize(width: 178, height: 118)
    private static let figure = CGSize(width: 89, height: 118.6)
    private static let duoReach = (top: -6.0, leading: -10.0, bottom: -8.0)
    private static let meAt = 6.0
    private static let partnerAt = 83.0
    private static let nameGap = 6.0
    private static let nameLift = 14.0
}

/// A squadmate's nickname, or 队友 for one without a character.
struct RecordsMateName: View {
    let mate: RecordMate

    var body: some View { text }
}

/// 收到加油 / 送出加油: the reactions, and the squadmate with the most, by their head.
struct CheersTile: View {
    let label: Text
    let cheers: SquadStanding.Cheers
    let received: Bool
    let order: Int
    let intro: RecordsIntro
    let cast: RecordsCast
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        RecordsTile {
            RecordsLabel(text: label)
            RecordsNumber(value: cheers.count, unit: Text("次", bundle: .module), progress: intro.number(order))
            if let top = cheers.top {
                HStack(spacing: Self.gap) {
                    MemberHead(player: cast.heads[top.mate.member], size: Self.head, rim: .none)
                        .background(Color(role: .fgOnBrand, in: theme).opacity(0.12), in: .circle)
                        .accessibilityHidden(true)
                    let name = RecordsMateName(mate: top.mate).text
                    Group {
                        if received {
                            let count = String(top.count)
                            Text("\(name) 最多 · \(count) 次", bundle: .module)
                        } else {
                            Text("最常给 \(name)", bundle: .module)
                        }
                    }
                    .typeStyle(TypeRamp.caption)
                    .foregroundStyle(Color(role: .fgOnBrandMuted, in: theme))
                    .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private static let gap = 6.0
    private static let head = 26.0
}

extension RecordsMateName {
    /// The name as text inside a sentence.
    var text: Text {
        if let name = mate.character?.nickname, !name.isEmpty {
            Text(verbatim: name)
        } else {
            Text("队友", bundle: .module)
        }
    }
}
#endif
