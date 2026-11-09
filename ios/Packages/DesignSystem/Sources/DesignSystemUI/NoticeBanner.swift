#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// News that drops in over whatever page is open (a teammate's comment, the coach's reply, a store
/// that opened, the squad moving): a Liquid Glass capsule that drops from the top of the screen
/// like the Dynamic Island opening (approved 2026-11-02, design A; glass on every page 2026-11-08).
/// A round icon on the left, which carries the news's colour, one line of title, an optional
/// muted line under it (up to two, so a broadcast's message mostly reads whole; 通知 shows all of
/// it), and its button's words in a graphite pill: a tap anywhere on the banner takes it.
///
/// Shown with `.noticeBanner(item:onTap:content:)`, which drops it in, keeps it
/// `Motion.noticeHold`, and puts it away on a swipe up or a tap.
public struct NoticeBanner<Icon: View>: View {
    @Environment(\.sceneTheme) private var theme
    private let title: Text
    private let detail: Text?
    private let action: Text
    private let icon: Icon

    /// The icon's circle.
    public static var iconSize: Double { 36 }
    /// From the icon to the words, and from the capsule's ends to what is inside.
    private static var inset: Double { 9 }

    /// - Parameters:
    ///   - action: the button's words (去看看, 查看, 重发), in a pill at the end.
    ///   - icon: filled into a 36-point circle: a scene's `SceneBadge`, a store's mark, a
    ///     `NoticeSymbol` in the squad's colour.
    public init(_ title: Text, detail: Text? = nil, action: Text, @ViewBuilder icon: () -> Icon) {
        self.title = title
        self.detail = detail
        self.action = action
        self.icon = icon()
    }

    public var body: some View {
        HStack(spacing: Self.inset) {
            icon
                .frame(width: Self.iconSize, height: Self.iconSize)
                .clipShape(Circle())
                .environment(\.noticeSymbolTone, .scene)
            VStack(alignment: .leading, spacing: 1) {
                title
                    .typeStyle(TypeRamp.calloutEmphasis)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                if let detail {
                    detail
                        .typeStyle(TypeRamp.caption)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            NoticeActionLabel(action)
        }
        .padding(.leading, Self.inset)
        .padding(.trailing, Self.inset)
        .padding(.vertical, Self.inset)
        .sceneGlass(in: Capsule(style: .continuous), theme: theme)
        .accessibilityElement(children: .combine)
    }
}

/// A notice's button words in a graphite pill: at the end of a `NoticeBanner`, and under a 通知
/// row's words. It is a label, not a button: a tap on the banner or the row it sits in takes it.
public struct NoticeActionLabel: View {
    private let words: Text
    private static var height: Double { 26 }

    public init(_ words: Text) {
        self.words = words
    }

    public var body: some View {
        words
            .typeStyle(TypeRamp.tabSelected)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(Color(role: .fgOnBrand, in: .gym))
            .padding(.horizontal, Space.s)
            .frame(height: Self.height)
            .background(Capsule().fill(Color(role: .bgBrand, in: .gym)))
    }
}

/// What a `NoticeSymbol`'s circle is painted with.
public enum NoticeSymbolTone: Sendable {
    /// Graphite: a 通知 row's icon, and the app's own news on a banner (a post that didn't go out).
    case brand
    /// The scene's colour: news from the squad on a banner, which sets it for its icon.
    case scene
}

extension EnvironmentValues {
    /// How a `NoticeSymbol` without a tone of its own is painted: a banner sets `.scene`.
    @Entry public var noticeSymbolTone: NoticeSymbolTone = .brand
}

/// A symbol in a circle, for news without a picture of its own: a notice's icon on its banner, in
/// the squad's colour, and on its 通知 row, in graphite.
public struct NoticeSymbol: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.noticeSymbolTone) private var placedTone
    private let systemImage: String
    private let tone: NoticeSymbolTone?

    /// - Parameter tone: graphite for the app's own news on a banner too; nil paints it as its
    ///   place does (graphite on a row, the scene's colour on a banner).
    public init(systemImage: String, tone: NoticeSymbolTone? = nil) {
        self.systemImage = systemImage
        self.tone = tone
    }

    public var body: some View {
        let scene = (tone ?? placedTone) == .scene
        ZStack {
            Color(role: scene ? .bgAccent : .bgBrand, in: scene ? theme : .gym)
            Image(systemName: systemImage)
                .font(.system(size: Sizing.smallIcon, weight: .semibold))
                .foregroundStyle(Color(role: scene ? .fgOnAccent : .fgOnBrand, in: scene ? theme : .gym))
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

    @ViewBuilder func body(content: Content) -> some View {
        // With none waiting the banner stays exactly as it was, nothing behind it.
        if count == 0 {
            content
        } else {
            edges(behind: content)
        }
    }

    private func edges(behind content: Content) -> some View {
        content
            .background(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    ForEach((1...count).reversed(), id: \.self) { edge in
                        Capsule(style: .continuous)
                            .fill(.regularMaterial)
                            .opacity(edge == 1 ? 1 : 0.7)
                            .frame(height: 2 * Self.peek * Double(edge))
                            .padding(.horizontal, Self.narrowing * Double(edge))
                            .offset(y: Self.peek * Double(edge))
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
                    // One element whatever the banner wears behind it (the edges of notices
                    // waiting), so VoiceOver and UI tests read its words as one label.
                    .accessibilityElement(children: .combine)
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
