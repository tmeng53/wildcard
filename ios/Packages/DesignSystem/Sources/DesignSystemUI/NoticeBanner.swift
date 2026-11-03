#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// News that nobody on the scene can tell (the squad moved to another scene, a store opened, a
/// prop unlocked): a brand capsule that drops from the top of the screen like the Dynamic Island
/// opening (approved 2026-11-02, design A). A round icon on the left, one line of title, an
/// optional muted second line and a chevron when a tap goes somewhere. Teammates' own news (who
/// joined, who is captain) stays in their speech bubbles on the scene.
///
/// Shown with `.noticeBanner(item:onTap:content:)`, which drops it in, keeps it
/// `Motion.noticeHold`, and puts it away on a swipe up or a tap.
public struct NoticeBanner<Icon: View>: View {
    private let title: Text
    private let detail: Text?
    private let showsChevron: Bool
    private let icon: Icon

    /// The icon's circle.
    public static var iconSize: Double { 36 }
    /// From the icon to the words, and from the capsule's ends to what is inside.
    private static var inset: Double { 9 }

    /// - Parameters:
    ///   - showsChevron: a tap opens somewhere (the store that opened); without it a tap only puts
    ///     the banner away.
    ///   - icon: filled into a 36-point circle: a scene's `SceneBadge`, a store's mark, a prop.
    public init(_ title: Text, detail: Text? = nil, showsChevron: Bool = false, @ViewBuilder icon: () -> Icon) {
        self.title = title
        self.detail = detail
        self.showsChevron = showsChevron
        self.icon = icon()
    }

    public var body: some View {
        let ink = Color(role: .fgOnBrand, in: .gym)
        HStack(spacing: Self.inset) {
            icon
                .frame(width: Self.iconSize, height: Self.iconSize)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
                title
                    .typeStyle(TypeRamp.calloutEmphasis)
                    .foregroundStyle(ink)
                if let detail {
                    detail
                        .typeStyle(TypeRamp.caption)
                        .foregroundStyle(ink.opacity(0.62))
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.6))
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, Self.inset)
        .padding(.trailing, Space.m)
        .padding(.vertical, Self.inset)
        .background(Capsule(style: .continuous).fill(Color(role: .bgBrand, in: .gym)))
        .accessibilityElement(children: .combine)
    }
}

/// A scene's colour, pattern and icon in a circle: the scene in a `NoticeBanner`.
public struct SceneBadge: View {
    private let scene: SceneTheme

    public init(_ scene: SceneTheme) {
        self.scene = scene
    }

    public var body: some View {
        TilePattern(scene: scene)
            .accessibilityHidden(true)
    }
}

extension EnvironmentValues {
    /// How long a `NoticeBanner` stays before it goes by itself: `Motion.noticeHold`, longer only
    /// in UI tests, whose busy simulators can take longer than that to reach it.
    @Entry public var noticeHold: Double = Motion.noticeHold
}

extension View {
    /// Drops `content(item)` in from the top while `item` is set, over everything under it, and
    /// puts it away after `noticeHold` (the environment's, `Motion.noticeHold` unless a UI test asks), on a swipe up, or on a tap (which also calls
    /// `onTap`). The caller keeps the queue: setting the next item shows it once this one is
    /// gone. It sits just under the status bar, clear of the Dynamic Island, which would hide
    /// its middle on a phone that has one. With Reduce Motion on, it fades instead of dropping.
    public func noticeBanner<Item: Identifiable, Banner: View>(
        item: Binding<Item?>, onTap: @escaping (Item) -> Void = { _ in },
        @ViewBuilder content: @escaping (Item) -> Banner
    ) -> some View {
        overlay(alignment: .top) {
            NoticePresenter(item: item, onTap: onTap, content: content)
        }
    }
}

private struct NoticePresenter<Item: Identifiable, Banner: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.noticeHold) private var hold
    @Binding var item: Item?
    let onTap: (Item) -> Void
    let content: (Item) -> Banner
    @State private var drag: Double = 0

    /// From the top of the safe area, just under the status bar and the Dynamic Island.
    private static var top: Double { 4 }
    /// How far up a swipe puts it away.
    private static var dismissDrag: Double { 16 }

    var body: some View {
        ZStack {
            if let shown = item {
                content(shown)
                    .padding(.horizontal, Space.pageMargin)
                    .padding(.top, Self.top)
                    .offset(y: min(0, drag))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        put(away: shown)
                        onTap(shown)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { drag = $0.translation.height }
                            .onEnded { value in
                                if value.translation.height < -Self.dismissDrag {
                                    put(away: shown)
                                } else {
                                    withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { drag = 0 }
                                }
                            }
                    )
                    .task(id: shown.id) {
                        try? await Task.sleep(for: .seconds(hold))
                        guard !Task.isCancelled else { return }
                        put(away: shown)
                    }
                    .transition(transition)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("notice.banner")
            }
        }
        .animation(.wildcard(Motion.notice, reduceMotion: reduceMotion), value: item?.id)
    }

    /// Out of the top of the screen, shrinking up towards the Dynamic Island; a fade with
    /// Reduce Motion on.
    private var transition: AnyTransition {
        guard !reduceMotion else { return AnyTransition.opacity }
        return AnyTransition.scale(scale: 0.6, anchor: .top)
            .combined(with: .offset(y: -40))
            .combined(with: .opacity)
    }

    private func put(away shown: Item) {
        guard item?.id == shown.id else { return }
        drag = 0
        withAnimation(.wildcard(Motion.notice.exit, reduceMotion: reduceMotion)) { item = nil }
    }
}
#endif
