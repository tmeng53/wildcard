#if os(iOS)
import AvatarUI
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SportsUI
import SwiftUI

/// 动感单车 ━━━━━ 6次 on a place's page: an icon disc, the name, a bar as long as its share of the
/// most, and the count.
struct PlaceTallyRow: View {
    @Environment(\.sceneTheme) private var theme
    let symbol: String
    let name: Text
    let count: Int
    let most: Int

    /// The icon's disc, the design's.
    private static let disc: CGFloat = 28
    private static let barHeight: CGFloat = 8

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: symbol)
                .font(.system(size: Sizing.smallIcon - 2, weight: .semibold))
                .foregroundStyle(Color(role: .fgOnInk, in: theme))
                .frame(width: Self.disc, height: Self.disc)
                .background(Color(role: .bgInk, in: theme), in: Circle())
                .accessibilityHidden(true)
            name
                .typeStyle(TypeRamp.body)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Capsule()
                .fill(Color(role: .bgSubtle, in: theme))
                .overlay(alignment: .leading) {
                    GeometryReader { bar in
                        Capsule()
                            .fill(Color(role: .fgDefault, in: theme))
                            .frame(width: barWidth(in: bar.size.width))
                    }
                }
                .frame(height: Self.barHeight)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: Space.xxs / 2) {
                Text(verbatim: "\(count)")
                    .typeStyle(TypeRamp.scoreSmall)
                Text(copy: "次", bundle: .module)
                    .typeStyle(TypeRamp.caption)
            }
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .frame(minWidth: Space.xl, alignment: .trailing)
        }
        .frame(minHeight: Sizing.minimumTapTarget)
        .accessibilityElement(children: .combine)
    }

    /// Its share of the most, at least a round end; none for a count of 0.
    private func barWidth(in track: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        return max(Self.barHeight, track * Double(count) / Double(max(most, 1)))
    }
}

/// A post on a place's page: its author's head, 小鱼 · 动感单车 45 分钟, and its day.
struct PlaceVisitRow: View {
    @Environment(\.sceneTheme) private var theme
    let visit: PlaceVisit
    let model: FeedModel
    let showsDivider: Bool

    private static let head: CGFloat = 36

    var body: some View {
        HStack(spacing: Space.s) {
            MemberHead(player: model.head(of: visit.member), size: Self.head)
            Text(verbatim: model.displayName(of: visit.member)).bold() + Text(verbatim: " · ") + what
            Spacer(minLength: Space.s)
            DayHeading(visit.day, today: model.store.today()).title
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
        }
        .typeStyle(TypeRamp.body)
        .foregroundStyle(Color(role: .fgDefault, in: theme))
        .lineLimit(1)
        .padding(.vertical, Space.s)
        .overlay(alignment: .bottom) {
            if showsDivider { Hairline(on: .page) }
        }
        .contentShape(Rectangle())
    }

    /// 动感单车 45 分钟, 健康餐.
    private var what: Text {
        switch visit.kind {
        case .trained(let activity):
            let sport = activity?.name ?? CheckInKind.trained.fullName
            guard let minutes = visit.minutes else { return sport }
            return sport + Text(verbatim: " ") + Text(copy: "\(minutes) 分钟", bundle: .module)
        case .healthyMeal: return CheckInKind.healthyMeal.fullName
        case .cheatMeal: return CheckInKind.cheatMeal.fullName
        }
    }
}

extension PlaceKind {
    /// What kind of place it is, under its name: 健身房, 餐厅.
    var name: Text {
        switch self {
        case .gym: Text(copy: "健身房", bundle: .module)
        case .food: Text(copy: "餐厅", bundle: .module)
        case .cafe: Text(copy: "咖啡馆", bundle: .module)
        case .market: Text(copy: "超市", bundle: .module)
        case .shop: Text(copy: "商店", bundle: .module)
        case .park: Text(copy: "公园", bundle: .module)
        case .beach: Text(copy: "海滩", bundle: .module)
        case .sport: Text(copy: "运动场", bundle: .module)
        case .other: Text(copy: "地点", bundle: .module)
        }
    }
}
#endif
