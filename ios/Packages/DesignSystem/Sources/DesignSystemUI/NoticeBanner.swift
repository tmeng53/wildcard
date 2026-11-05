#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// News that nobody on the scene can tell (the squad moved to another scene, a store opened, a
/// prop unlocked): a brand capsule that drops from the top of the screen like the Dynamic Island
/// opening (approved 2026-11-02, design A). A round icon on the left, one line of title, an
/// optional muted second line, and a chevron when a tap goes somewhere, or the button's words in a
/// white pill when it has one (a broadcast's 去商店街看看; approved 2026-11-04). Teammates' own news
/// (who joined, who is captain) stays in their speech bubbles on the scene.
///
/// Shown with `.noticeBanner(item:onTap:content:)`, which drops it in, keeps it
/// `Motion.noticeHold`, and puts it away on a swipe up or a tap.
public struct NoticeBanner<Icon: View>: View {
    private let title: Text
    private let detail: Text?
    private let showsChevron: Bool
    private let action: Text?
    private let icon: Icon

    /// The icon's circle.
    public static var iconSize: Double { 36 }
    /// From the icon to the words, and from the capsule's ends to what is inside.
    private static var inset: Double { 9 }

    /// - Parameters:
    ///   - showsChevron: a tap opens somewhere (the store that opened); without it a tap only puts
    ///     the banner away.
    ///   - action: a button's words, in a pill in place of the chevron; a tap anywhere on the
    ///     banner takes it.
    ///   - icon: filled into a 36-point circle: a scene's `SceneBadge`, a store's mark, a prop.
    public init(
        _ title: Text, detail: Text? = nil, showsChevron: Bool = false, action: Text? = nil,
        @ViewBuilder icon: () -> Icon
    ) {
        self.title = title
        self.detail = detail
        self.showsChevron = showsChevron
        self.action = action
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
            if let action {
                NoticeActionLabel(action, on: .brand)
            } else if showsChevron {
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

/// A notice's button words in a pill: white on the graphite banner, graphite under a 通知 row's
/// words. It is a label, not a button: a tap on the banner or the row it sits in takes it.
public struct NoticeActionLabel: View {
    public enum Placement: Sendable {
        /// On a `NoticeBanner`.
        case brand
        /// Under a row's words on a page.
        case page
    }

    private let words: Text
    private let placement: Placement
    private static var height: Double { 26 }

    public init(_ words: Text, on placement: Placement) {
        (self.words, self.placement) = (words, placement)
    }

    public var body: some View {
        words
            .typeStyle(TypeRamp.tabSelected)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(Color(role: placement == .brand ? .fgDefault : .fgOnBrand, in: .gym))
            .padding(.horizontal, Space.s)
            .frame(height: Self.height)
            .background(
                Capsule().fill(Color(role: placement == .brand ? .fgOnBrand : .bgBrand, in: .gym)))
    }
}

/// A symbol on graphite, for news without a picture of its own: a notice's icon on its banner and
/// its 通知 row.
public struct NoticeSymbol: View {
    private let systemImage: String

    public init(systemImage: String) {
        self.systemImage = systemImage
    }

    public var body: some View {
        ZStack {
            Color(role: .bgBrand, in: .gym)
            Image(systemName: systemImage)
                .font(.system(size: Sizing.smallIcon, weight: .semibold))
                .foregroundStyle(Color(role: .fgOnBrand, in: .gym))
        }
        .accessibilityHidden(true)
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

extension View {
    /// Drops `content(item)` in from the top while `item` is set, over everything under it, and
    /// puts it away after `hold` seconds (never when `hold` gives nil for it, as for a banner
    /// with a button), on a swipe up, or on a tap (which also calls `onTap`). The caller keeps the queue: setting the next item shows it once this one is
    /// gone. It sits just under the status bar, clear of the Dynamic Island, which would hide
    /// its middle on a phone that has one. With Reduce Motion on, it fades instead of dropping.
    public func noticeBanner<Item: Identifiable, Banner: View>(
        item: Binding<Item?>, hold: @escaping (Item) -> Double? = { _ in Motion.noticeHold },
        onTap: @escaping (Item) -> Void = { _ in },
        @ViewBuilder content: @escaping (Item) -> Banner
    ) -> some View {
        overlay(alignment: .top) {
            NoticePresenter(item: item, hold: hold, onTap: onTap, content: content)
        }
    }
}

extension View {
    /// Under a `NoticeBanner`, an edge of a capsule for each banner still to come, at most two,
    /// as iOS stacks its notifications (approved C, 2026-11-05); nothing when none waits.
    public func noticesWaiting(_ count: Int) -> some View {
        modifier(NoticesWaiting(count: min(max(count, 0), 2)))
    }
}

private struct NoticesWaiting: ViewModifier {
    let count: Int
    /// How far each edge shows under the one above it, and how much narrower it is at each end.
    private static var peek: Double { 5 }
    private static var narrowing: Double { 10 }

    func body(content: Content) -> some View {
        content
            .background(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    ForEach((1...max(count, 1)).reversed(), id: \.self) { edge in
                        if edge <= count {
                            Capsule(style: .continuous)
                                .fill(Color(role: .bgBrand, in: .gym).opacity(edge == 1 ? 0.55 : 0.3))
                                .frame(height: 2 * Self.peek * Double(edge))
                                .padding(.horizontal, Self.narrowing * Double(edge))
                                .offset(y: Self.peek * Double(edge))
                        }
                    }
                }
                .accessibilityHidden(true)
            }
    }
}

private struct NoticePresenter<Item: Identifiable, Banner: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var item: Item?
    let hold: (Item) -> Double?
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
                        guard let hold = hold(shown) else { return }
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
