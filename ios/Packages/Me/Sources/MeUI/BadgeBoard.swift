#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SportsUI
import SwiftUI

/// One badge on the board: the badge, ×N when won more than once, a tick on the one worn, NEW
/// until it is opened on this phone, and its title under it.
struct BadgeCell: View {
    let title: BoardTitle
    let isWorn: Bool
    var isNew = false
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(spacing: Space.xxs) {
            TitleBadgeView(
                shape: title.badge.shape, colour: title.badge.colour, tone: title.badge.tone, glyph: title.badge.glyph,
                size: BoardMetrics.badge
            )
            .frame(width: BoardMetrics.slot, height: BoardMetrics.slot)
            .overlay(alignment: .topTrailing) {
                if title.times > 1 {
                    Text(verbatim: "×\(title.times)")
                        .typeStyle(TypeRamp.scoreCaption)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .padding(.horizontal, Space.xxs)
                        .frame(minWidth: BoardMetrics.chip, minHeight: BoardMetrics.chip - 2)
                        .background(Color(role: .bgCanvas, in: theme), in: Capsule())
                        .offset(x: Space.xxs / 2, y: -Space.xxs / 2)
                }
            }
            .badgeMarks(isWorn: isWorn, isNew: isNew)
            Text(verbatim: title.title)
                .typeStyle(isWorn ? TypeRamp.footnoteEmphasis : TypeRamp.caption)
                .foregroundStyle(Color(role: .fgOnInk, in: theme))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title.title))
        .accessibilityValue(
            isWorn ? Text(copy: "已装备", bundle: .module) : Text(verbatim: title.times > 1 ? "×\(title.times)" : ""))
    }
}

extension View {
    /// A badge's tick when it is worn, at its bottom right, and NEW when it is new, at its top
    /// left.
    fileprivate func badgeMarks(isWorn: Bool, isNew: Bool) -> some View {
        modifier(BadgeMarksOverlay(isWorn: isWorn, isNew: isNew))
    }
}

private struct BadgeMarksOverlay: ViewModifier {
    let isWorn: Bool
    let isNew: Bool
    @Environment(\.sceneTheme) private var theme

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                if isWorn {
                    Image(systemName: "checkmark")
                        .font(.system(size: BoardMetrics.tick, weight: .bold))
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .frame(width: BoardMetrics.chip - 2, height: BoardMetrics.chip - 2)
                        .background(Color(role: .bgCanvas, in: theme), in: Circle())
                        .offset(x: Space.xxs / 2, y: Space.xxs / 2)
                        .accessibilityIdentifier("me.badgeWorn")
                }
            }
            .overlay(alignment: .topLeading) {
                if isNew {
                    InkTag.newOnInk
                        .offset(x: -Space.xxs / 2, y: -Space.xxs / 2)
                        .accessibilityIdentifier("me.badgeNew")
                }
            }
    }
}

/// A badge the Wildcard team gave (捉虫队, 点子王): a ticket in its own colour, ×N when given more
/// than once, a tick when worn, NEW until it is opened on this phone, and its name under it.
struct TeamBadgeCell: View {
    let badge: TeamBadge
    let isWorn: Bool
    var isNew = false
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(spacing: Space.xxs) {
            TitleBadgeView(
                shape: TitleBadgeView.Shape.ticket.rawValue, colour: badge.id, tone: badge.tone, glyph: badge.glyph,
                size: BoardMetrics.badge
            )
            .frame(width: BoardMetrics.slot, height: BoardMetrics.slot)
            .overlay(alignment: .topTrailing) {
                if badge.times > 1 {
                    Text(verbatim: "×\(badge.times)")
                        .typeStyle(TypeRamp.scoreCaption)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .padding(.horizontal, Space.xxs)
                        .frame(minWidth: BoardMetrics.chip, minHeight: BoardMetrics.chip - 2)
                        .background(Color(role: .bgCanvas, in: theme), in: Capsule())
                        .offset(x: Space.xxs / 2, y: -Space.xxs / 2)
                }
            }
            .badgeMarks(isWorn: isWorn, isNew: isNew)
            Text(verbatim: badge.name.localized)
                .typeStyle(TypeRamp.caption)
                .foregroundStyle(Color(role: .fgOnInk, in: theme))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: badge.name.localized))
        .accessibilityValue(
            isWorn ? Text(copy: "已装备", bundle: .module) : Text(verbatim: badge.times > 1 ? "×\(badge.times)" : ""))
    }
}

/// The board's last slot: a dashed ring for the badge the next Sunday may bring.
struct NextBadgeCell: View {
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(spacing: Space.xxs) {
            Circle()
                .strokeBorder(
                    Color(role: .fgMuted, in: theme),
                    style: StrokeStyle(lineWidth: Sizing.selectionStroke, dash: [4, 3])
                )
                .frame(width: BoardMetrics.badge, height: BoardMetrics.badge)
                .frame(width: BoardMetrics.slot, height: BoardMetrics.slot)
            Text(copy: "周日揭晓", bundle: .module)
                .typeStyle(TypeRamp.caption)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("me.nextBadge")
    }
}

/// The board's sizes, from the approved design.
enum BoardMetrics {
    static let badge: Double = 46
    static let slot: Double = 52
    static let chip: Double = 20
    static let tick: Double = 9
}
#endif
