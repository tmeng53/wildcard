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

            SceneBand(isOpen: isOpen)
                .frame(height: 340)
                .overlay(alignment: .bottom) {
                    VStack(spacing: Space.l) {
                        CheckInControl(isOpen: $isOpen)
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

/// The scene's floor: a quiet wash with faint signature lane lines, so the solid 打卡 button is
/// the only strong color. Blurred lightly while a check-in is open.
private struct SceneBand: View {
    @Environment(\.sceneTheme) private var theme
    let isOpen: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color(role: .signatureWash, in: theme)
                Rectangle()
                    .fill(Color(role: .signature, in: theme).opacity(0.35))
                    .frame(height: Space.xxs)
                ForEach(1..<4, id: \.self) { lane in
                    Rectangle()
                        .fill(Color(role: .signature, in: theme).opacity(0.22))
                        .frame(width: 2)
                        .offset(x: proxy.size.width * Double(lane) / 4 - 1)
                }
            }
            .blur(radius: isOpen ? Scrim.blurRadius : 0)
            .overlay(Color(Scrim.tint).opacity(isOpen ? Scrim.tintOpacity : 0))
            .animation(.easeOut(duration: isOpen ? Scrim.fadeIn : Scrim.fadeOut), value: isOpen)
        }
        .accessibilityHidden(true)
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
            ProgressTrack(fraction: 18.0 / 25.0)
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

private struct ProgressTrack: View {
    @Environment(\.sceneTheme) private var theme
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(role: .divider, in: theme))
                Capsule()
                    .fill(Color(role: .progressFill, in: theme))
                    .overlay {
                        // A fill too faint to hold its shape on white (gym's volt) gets a signature edge.
                        if theme.colors.progressFill.contrastRatio(with: Palette.white) < 3 {
                            Capsule().strokeBorder(Color(role: .signature, in: theme), lineWidth: 1)
                        }
                    }
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: Space.xs)
        .accessibilityHidden(true)
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

// MARK: - 打卡 and its capsules

private struct CheckInControl: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isOpen: Bool
    @State private var picked: Meaning?

    var body: some View {
        ZStack {
            if isOpen {
                ForEach(Array(Meaning.allCases.enumerated()), id: \.element) { index, meaning in
                    CheckInCapsule(meaning: meaning) {
                        picked = meaning
                        withAnimation(.wildcard(Motion.burst, reduceMotion: reduceMotion)) { isOpen = false }
                    }
                    .offset(x: BurstLayout.offset(for: meaning).x, y: BurstLayout.offset(for: meaning).y)
                    .transition(burst(for: meaning, index: index))
                }
            }
            CheckInButton(isOpen: $isOpen)
        }
        .frame(height: Sizing.checkInHeight)
        // Haptics only where the spec puts them: the burst opening and picking a type.
        .sensoryFeedback(.impact(weight: .light), trigger: isOpen) { _, opened in opened }
        .sensoryFeedback(.selection, trigger: picked)
    }

    /// Out of the button along the arc, staggered; back in faster, in reverse order.
    private func burst(for meaning: Meaning, index: Int) -> AnyTransition {
        if reduceMotion {
            return .opacity.animation(.easeOut(duration: Motion.reducedDuration))
        }
        let offset = BurstLayout.offset(for: meaning)
        let shape = AnyTransition.offset(x: -offset.x, y: -offset.y)
            .combined(with: .scale(scale: 0.4))
            .combined(with: .opacity)
        let count = Meaning.allCases.count
        return .asymmetric(
            insertion: shape.animation(.wildcard(Motion.burst).delay(Motion.burstStagger * Double(index))),
            removal: shape.animation(
                .easeIn(duration: Motion.collapseDuration)
                    .delay(Motion.collapseStagger * Double(count - 1 - index)))
        )
    }
}

/// The primary action: a solid signature capsule. Its plus turns into a cross and it keeps a
/// word (收起) when open, so it is never an icon alone.
private struct CheckInButton: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isOpen: Bool

    var body: some View {
        Button {
            withAnimation(.wildcard(Motion.burst, reduceMotion: reduceMotion)) { isOpen.toggle() }
        } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: "plus")
                    .fontWeight(.bold)
                    .rotationEffect(.degrees(isOpen ? 135 : 0))
                    .accessibilityHidden(true)
                (isOpen ? Text("收起", bundle: .module) : Text("打卡", bundle: .module))
                    .typeStyle(TypeRamp.action)
            }
            .foregroundStyle(Color(role: .onSignature, in: theme))
            .padding(.horizontal, Space.l)
            .frame(height: Sizing.checkInHeight)
            .background(Color(role: .signature, in: theme), in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier("styleguide.checkin")
    }
}

private struct CheckInCapsule: View {
    @Environment(\.sceneTheme) private var theme
    let meaning: Meaning
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                Image(systemName: meaning.symbol)
                    .font(.system(size: Sizing.capsuleGlyph, weight: .semibold))
                    .frame(width: Sizing.capsuleIcon, height: Sizing.capsuleIcon)
                    .foregroundStyle(Color(role: meaning.ink, in: theme))
                    .accessibilityHidden(true)
                meaning.capsuleLabel
                    .typeStyle(TypeRamp.callout)
                    .foregroundStyle(Color(role: .textPrimary, in: theme))
                    .fixedSize()
            }
            .padding(.horizontal, Space.m)
            .frame(height: Sizing.capsuleHeight)
            .frosted(white: Frost.capsuleFill, in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier("styleguide.capsule.\(meaning.rawValue)")
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
