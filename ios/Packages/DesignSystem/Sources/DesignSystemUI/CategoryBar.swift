#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// One item of a `CategoryBar`.
public struct CategoryBarItem<ID: Hashable>: Identifiable {
    public let id: ID
    public let title: Text
    /// A symbol in front of the title, for an item unlike the rest (出赛表's 我的每周计划).
    public let systemImage: String?
    /// Sets the item apart from the ones before it with a hairline.
    public let startsGroup: Bool
    /// For UI tests; the bar puts it on the item's button.
    public let accessibilityIdentifier: String?
    /// False for an item shown greyed that can't be picked (出赛表's 还未入队).
    public let isEnabled: Bool
    /// Picks behind one item (出赛表's 往期): the item opens the system menu of them, wears the
    /// one picked as its title while it is the selection, and carries a chevron. Its own `id`
    /// should be the first option's.
    public let options: [CategoryBarItem<ID>]

    public init(
        id: ID, title: Text, systemImage: String? = nil, startsGroup: Bool = false,
        accessibilityIdentifier: String? = nil, isEnabled: Bool = true, options: [CategoryBarItem<ID>] = []
    ) {
        self.options = options
        self.isEnabled = isEnabled
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.startsGroup = startsGroup
        self.accessibilityIdentifier = accessibilityIdentifier
    }
}

/// 「我在哪」: a horizontally scrolling row of categories or tabs. Every item has the same
/// padding; the selected one sits on a solid ink capsule that slides between items, never an
/// underline or a grey block. The edges fade only where
/// there is more to scroll. Pass `isPinned` while the bar is stuck over scrolled content, so it
/// gets a solid page band behind it, up under the status bar; otherwise it has no background.
public struct CategoryBar<ID: Hashable>: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var indicator
    @Binding private var selection: ID
    /// The item whose glass menu of options is open.
    @State private var openMenu: ID?
    private let items: [CategoryBarItem<ID>]
    private let isPinned: Bool
    /// Every item's padding at each end, so the items space evenly.
    private static var itemInset: Double { Space.s + 2 }

    public init(_ items: [CategoryBarItem<ID>], selection: Binding<ID>, isPinned: Bool = false) {
        self.items = items
        _selection = selection
        self.isPinned = isPinned
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(items) { item in
                        if item.startsGroup {
                            Rectangle()
                                .fill(Color(role: .borderDefault, in: theme))
                                .frame(width: 1, height: Sizing.compactControl - Space.s)
                                .padding(.horizontal, Space.xxs)
                                .accessibilityHidden(true)
                        }
                        itemButton(item).id(item.id)
                    }
                }
                .padding(.horizontal, Space.xs)
            }
            .scrollIndicators(.hidden)
            .horizontalScrollFade()
            // A selection that starts past the edge (the last item, say) opens in view, with its
            // neighbours either side where there are any, also when the items arrive after the bar.
            .onChange(of: items.map(\.id), initial: true) {
                proxy.scrollTo(selection, anchor: .center)
            }
            .onChange(of: selection) { _, selected in
                // Centred, so the items either side show too and the next one is never hidden
                // past the edge.
                withAnimation(.wildcard(Motion.page, reduceMotion: reduceMotion)) {
                    proxy.scrollTo(selected, anchor: .center)
                }
            }
        }
        .background {
            if isPinned {
                Color(role: .bgCanvas, in: theme).ignoresSafeArea(edges: .top)
            }
        }
    }

    @ViewBuilder private func itemButton(_ item: CategoryBarItem<ID>) -> some View {
        if item.options.isEmpty {
            plainItem(item)
        } else {
            menuItem(item)
        }
    }

    private func plainItem(_ item: CategoryBarItem<ID>) -> some View {
        let isSelected = item.id == selection
        return Button {
            pick(item.id)
        } label: {
            itemLabel(item.title, symbol: item.systemImage, isSelected: isSelected, isEnabled: item.isEnabled)
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(ifPresent: item.accessibilityIdentifier)
    }

    /// The app's glass menu of the item's options, from a label like the other items' with a chevron.
    private func menuItem(_ item: CategoryBarItem<ID>) -> some View {
        let picked = item.options.first { $0.id == selection }
        return Button {
            openMenu = item.id
        } label: {
            itemLabel(
                picked?.title ?? item.title, symbol: "chevron.down", trailingSymbol: true, isSelected: picked != nil,
                isEnabled: item.isEnabled)
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
        .accessibilityAddTraits(picked != nil ? .isSelected : [])
        .accessibilityIdentifier(ifPresent: item.accessibilityIdentifier)
        .glassMenu(
            isPresented: Binding(get: { openMenu == item.id }, set: { if !$0 { openMenu = nil } }),
            items: item.options.enumerated().map { index, option in
                GlassMenuItem(
                    option.title, isSelected: option.id == selection, isEnabled: option.isEnabled,
                    id: option.accessibilityIdentifier ?? "categoryBar.option.\(index)"
                ) {
                    pick(option.id)
                }
            })
    }

    private func pick(_ id: ID) {
        withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { selection = id }
    }

    private func itemLabel(
        _ title: Text, symbol: String?, trailingSymbol: Bool = false, isSelected: Bool, isEnabled: Bool
    ) -> some View {
        HStack(spacing: Space.xxs) {
            if let symbol, !trailingSymbol {
                Image(systemName: symbol)
                    .font(.system(size: Sizing.smallIcon, weight: .semibold))
                    .accessibilityHidden(true)
            }
            title
            if let symbol, trailingSymbol {
                Image(systemName: symbol)
                    .font(.system(size: Sizing.smallIcon * 0.8, weight: .semibold))
                    .accessibilityHidden(true)
            }
        }
        .typeStyle(isSelected ? TypeRamp.calloutEmphasis : TypeRamp.callout)
        .foregroundStyle(Color(role: isSelected ? .bgCanvas : isEnabled ? .fgMuted : .fgSubtle, in: theme))
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, Self.itemInset)
        // The pill hugs this box, so it grows with Dynamic Type instead of clipping.
        .frame(minHeight: Sizing.compactControl)
        .background {
            if isSelected {
                Capsule()
                    .fill(Color(role: .fgDefault, in: theme))
                    .matchedGeometryEffect(id: "selection", in: indicator)
            }
        }
        .frame(minHeight: Sizing.minimumTapTarget)
        .contentShape(Rectangle())
    }
}

extension View {
    /// Fades a horizontal scroll view's edges, each only while there is more to scroll that way,
    /// so no label is cut off hard and nothing fades at rest.
    public func horizontalScrollFade() -> some View {
        modifier(HorizontalScrollFade())
    }

    @ViewBuilder
    func accessibilityIdentifier(ifPresent identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}

private struct ScrollEdges: Equatable {
    var canScrollBack = false
    var canScrollForward = false
}

private struct HorizontalScrollFade: ViewModifier {
    @State private var edges = ScrollEdges()
    /// Fade widths at the leading and trailing edge, in points.
    private let leadingFade: Double = 24
    private let trailingFade: Double = 32

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: ScrollEdges.self) { geometry in
                let visible = geometry.visibleRect
                return ScrollEdges(
                    canScrollBack: visible.minX > 1,
                    canScrollForward: visible.maxX < geometry.contentSize.width - 1
                )
            } action: { _, newEdges in
                edges = newEdges
            }
            .mask {
                // A mask uses only alpha: black shows the content, clear hides it.
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: edges.canScrollBack ? leadingFade : 0)
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: edges.canScrollForward ? trailingFade : 0)
                }
                .animation(.easeOut(duration: Motion.reducedDuration), value: edges)
            }
    }
}
#endif
