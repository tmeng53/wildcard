#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// The top of the style guide: a scene switcher, the squad banner, and the scene band with the
/// 打卡 button, its capsules and the tab bar floating over it.
struct SceneStage: View {
    @Binding var theme: SceneTheme
    @State private var isOpen = false

    var body: some View {
        VStack(spacing: Space.m) {
            Picker(selection: $theme) {
                ForEach(SceneTheme.allCases, id: \.self) { scene in
                    scene.name.tag(scene)
                }
            } label: {
                Text("场景", bundle: .module)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("styleguide.theme")
            .padding(.horizontal, Space.gutter)

            SquadBanner()
                .padding(.horizontal, Space.gutter)
                .blur(radius: isOpen ? Scrim.blurRadius : 0)
                .animation(.easeOut(duration: isOpen ? Scrim.fadeIn : Scrim.fadeOut), value: isOpen)

            SceneFloor(isBlurred: isOpen)
                .frame(height: 340)
                .overlay(alignment: .bottom) {
                    VStack(spacing: Space.l) {
                        CheckInBurst(isOpen: $isOpen, identifierPrefix: "styleguide") { _ in }
                        TabBarSample()
                    }
                    .padding(.horizontal, Space.gutter)
                    .padding(.bottom, Space.l)
                }
        }
        .padding(.top, Space.s)
        .background(alignment: .bottom) {
            // Taller than the stage, so pulling the page down shows more wash, not a gap.
            Color(role: .signatureWash, in: theme).frame(height: 2000)
        }
    }
}

// MARK: - Squad banner

private struct SquadBanner: View {
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .top, spacing: Space.xs) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    HStack(spacing: 0) {
                        Text("第 42 周", bundle: .module)
                        Text(verbatim: " · ")
                        theme.name
                    }
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .signatureText, in: theme))
                    .padding(.horizontal, Space.xs)
                    .padding(.vertical, Space.xxs)
                    .background(Color(role: .signatureWash, in: theme), in: Capsule())
                    .padding(.bottom, Space.xxs)
                    Text("周三不练腿俱乐部", bundle: .module)
                        .typeStyle(TypeRamp.headline)
                        .foregroundStyle(Color(role: .textPrimary, in: theme))
                    Text("本周全队还差 7 次达标", bundle: .module)
                        .typeStyle(TypeRamp.caption)
                        .foregroundStyle(Color(role: .textSecondary, in: theme))
                }
                Spacer(minLength: 0)
                Score(
                    count: 18, goal: 25, countStyle: TypeRamp.scoreLarge, goalStyle: TypeRamp.scoreLargeDenominator)
            }
            ProgressBar(fraction: 18.0 / 25.0)
            HStack(spacing: Space.s) {
                AvatarRow()
                VStack(alignment: .leading, spacing: 2) {
                    Text("今天 3 人练了", bundle: .module)
                        .typeStyle(TypeRamp.callout)
                        .foregroundStyle(Color(role: .textPrimary, in: theme))
                    Text("1 人免责声明", bundle: .module)
                        .typeStyle(TypeRamp.caption)
                        .foregroundStyle(Color(role: .textSecondary, in: theme))
                }
                Spacer(minLength: 0)
                Rectangle()
                    .fill(Color(role: .divider, in: theme))
                    .frame(width: 1, height: Space.xl)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("我 · 本周", bundle: .module)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .textSecondary, in: theme))
                        .fixedSize()
                    Score(
                        count: 3, goal: 5, countStyle: TypeRamp.scoreSmall, goalStyle: TypeRamp.scoreSmallDenominator)
                }
            }
        }
        .padding(Space.m)
        .frosted(white: Frost.bannerFill, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("styleguide.banner")
    }
}

/// Placeholder avatars ringed by today's status: trained, disclaimer, not yet. Me last.
private struct AvatarRow: View {
    @Environment(\.sceneTheme) private var theme
    private let statuses: [ColorRole] = [
        .meaningTrained, .meaningTrained, .meaningTrained, .meaningDisclaimer, .divider,
    ]
    private let size: Double = 30

    var body: some View {
        HStack(spacing: -Space.xs) {
            ForEach(statuses.indices, id: \.self) { index in
                Circle()
                    .fill(Color(role: .surface, in: theme))
                    .overlay(Circle().strokeBorder(Color(role: .canvas, in: theme), lineWidth: 1))
                    .padding(3)
                    .overlay(Circle().strokeBorder(Color(role: statuses[index], in: theme), lineWidth: 2.5))
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Tab bar

private enum TabSample: String, CaseIterable {
    case today, highlights, schedule, profile

    var title: Text {
        switch self {
        case .today: Text("今天", bundle: .module)
        case .highlights: Text("名场面", bundle: .module)
        case .schedule: Text("出赛表", bundle: .module)
        case .profile: Text("我", bundle: .module)
        }
    }

    var symbol: String {
        switch self {
        case .today: "figure.run"
        case .highlights: "star"
        case .schedule: "list.bullet.rectangle"
        case .profile: "person"
        }
    }
}

/// A Liquid Glass tab bar (navigation is Liquid Glass, Tracy 2026-10-18): icon and word on
/// every item; the selected one in signature text on a light signature pill, the rest in
/// primary text.
private struct TabBarSample: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected = TabSample.today

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TabSample.allCases, id: \.self) { tab in
                let isSelected = tab == selected
                Button {
                    withAnimation(.wildcard(Motion.smooth, reduceMotion: reduceMotion)) { selected = tab }
                } label: {
                    HStack(spacing: Space.xxs) {
                        Image(systemName: tab.symbol).accessibilityHidden(true)
                        tab.title.fixedSize()
                    }
                    .typeStyle(TypeRamp.caption)
                    .foregroundStyle(Color(role: isSelected ? .signatureText : .textPrimary, in: theme))
                    .frame(maxWidth: .infinity, minHeight: Sizing.minimumTapTarget)
                    .background {
                        if isSelected {
                            Capsule().fill(Color(role: .signature, in: theme).opacity(Tint.selected))
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("styleguide.tab.\(tab.rawValue)")
            }
        }
        .padding(Space.xxs)
        .glassEffect(.regular, in: Capsule())
    }
}
#endif
