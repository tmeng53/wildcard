#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// One badge opened from the board, as the approved design draws it: a dark collectible card
/// whose top is the badge's colour, the badge large over the seam, the title, a chip for each week
/// it was won, the latest 颁奖词, and 装备 on the member's own card.
struct BadgeCard: View {
    let title: BoardTitle
    let isWorn: Bool
    /// Wears it; nil on a squadmate's card, which shows no button.
    let equip: (() -> Void)?
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            top
            VStack(spacing: Space.s) {
                Text(verbatim: title.title)
                    .typeStyle(TypeRamp.badgeTitle)
                    .foregroundStyle(Color(role: .fgOnInk, in: theme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityIdentifier("me.badgeCard.title")
                FlowRow {
                    ForEach(title.weeks, id: \.weekStart) { week in
                        Text(verbatim: Self.range(of: week.weekStart))
                            .typeStyle(TypeRamp.scoreCaption)
                            .monospacedDigit()
                            .foregroundStyle(Color(role: .fgOnInk, in: theme))
                            .padding(.horizontal, Space.xs)
                            .padding(.vertical, Space.xxs)
                            .overlay(Capsule().stroke(Color(role: .borderOnInk, in: theme), lineWidth: Sizing.hairline))
                    }
                }
                if let speech = title.latestSpeech {
                    Text(verbatim: speech)
                        .typeStyle(TypeRamp.callout)
                        .foregroundStyle(Color(role: .fgOnInkMuted, in: theme))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Space.xxs)
                        .accessibilityIdentifier("me.badgeCard.speech")
                }
                Spacer(minLength: Space.m)
                if let equip {
                    Button(action: equip) {
                        Text(isWorn ? "已装备" : "装备", bundle: .module)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OnInkButtonStyle())
                    .disabled(isWorn)
                    .accessibilityIdentifier("me.badgeCard.equip")
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Self.overlap + Space.s)
            .padding(.bottom, Space.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(role: .bgInk, in: theme))
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Radius.card * 2)
        // Contain, so the identifier names the card and not every control inside it.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("me.badgeCard")
    }

    /// The top in the badge's colour, the squad it was last won in and 每周战报 on its left (just
    /// 每周战报 when the API names no squad), ×N on its right, and the badge sitting over the seam.
    private var top: some View {
        TitleBadgeView.enamel(title.badge.colour)
            .frame(height: Self.topHeight)
            .overlay(alignment: .top) {
                // One row, so a long squad name shrinks and stops before ×N instead of under it.
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Group {
                        if let squad = title.latestSquadName {
                            Text("badge.from \(squad)", bundle: .module)
                        } else {
                            Text("每周战报", bundle: .module)
                        }
                    }
                    .typeStyle(TypeRamp.label)
                    .foregroundStyle(Color(role: .fgOnInk, in: theme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityIdentifier("me.badgeCard.from")
                    Spacer(minLength: 0)
                    if title.times > 1 {
                        Text(verbatim: "×\(title.times)")
                            .typeStyle(TypeRamp.scoreSmall)
                            .foregroundStyle(Color(role: .fgDefault, in: theme))
                            .padding(.horizontal, Space.xs)
                            .padding(.vertical, Space.xxs / 2)
                            .background(Color(role: .bgCanvas, in: theme), in: Capsule())
                            .fixedSize()
                            .accessibilityIdentifier("me.badgeCard.times")
                    }
                }
                .padding(Space.m)
            }
            .overlay(alignment: .bottom) {
                TitleBadgeView(
                    shape: title.badge.shape, colour: title.badge.colour, glyph: title.badge.glyph,
                    size: Self.badgeSize
                )
                .offset(y: Self.overlap)
            }
            .zIndex(1)
    }

    private static let topHeight: Double = 168
    private static let badgeSize: Double = 124
    /// How far the badge hangs below the top.
    private static var overlap: Double { badgeSize / 2 }

    /// "10.26 – 11.1": the Monday to the Sunday of a week.
    static func range(of weekStart: LocalDay) -> String {
        let end = weekStart.adding(days: 6)
        return "\(weekStart.month).\(weekStart.day) – \(end.month).\(end.day)"
    }
}

/// The badge card's one action: a white capsule on the dark card.
private struct OnInkButtonStyle: ButtonStyle {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .typeStyle(TypeRamp.action)
            .lineLimit(1)
            .foregroundStyle(Color(role: isEnabled ? .fgDefault : .fgOnInkMuted, in: theme))
            .frame(minHeight: Sizing.primaryControl)
            .background(
                Color(role: isEnabled ? .bgCanvas : .borderOnInk, in: theme), in: Capsule()
            )
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
#endif
