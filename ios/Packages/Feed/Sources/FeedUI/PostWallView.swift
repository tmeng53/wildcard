#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SportsUI
import SwiftUI

/// 我的动态 (历史动态): everything the member posted, as a wall of square tiles three to a row
/// under month headings, newest first (the approved design: canvas KEuPPx15JkeEYQwt6wYDRS,
/// board 2). A post with a photo shows its cover; one without is a block of its sport's scene
/// colour with its words on it. Each tile carries its date, sport or kind, minutes and emoji.
/// A brand page: the scene colours appear only on the tiles.
public struct PostWallView: View {
    @Environment(\.sceneTheme) private var theme
    @State private var store: PostWallStore
    private let back: () -> Void
    private let open: ((FeedPost) -> Void)?
    private let checkIn: () -> Void

    /// `open` shows a tapped post (tiles don't open while it's nil); `checkIn` goes to 今天 from
    /// the empty wall.
    public init(
        store: PostWallStore, back: @escaping () -> Void, open: ((FeedPost) -> Void)?,
        checkIn: @escaping () -> Void
    ) {
        _store = State(initialValue: store)
        self.back = back
        self.open = open
        self.checkIn = checkIn
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.s, pinnedViews: []) {
                HeaderButton(Text("返回", bundle: .module), systemImage: "chevron.left", action: back)
                    .accessibilityIdentifier("wall.back")
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("我的动态", bundle: .module)
                        .typeStyle(TypeRamp.largeTitle)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .accessibilityAddTraits(.isHeader)
                    if let counts = store.counts {
                        Text("发过 \(counts.posts) 条 · 收到 \(counts.reactions) 个表情", bundle: .module)
                            .typeStyle(TypeRamp.footnote)
                            .foregroundStyle(Color(role: .fgMuted, in: theme))
                            .accessibilityIdentifier("wall.counts")
                    }
                }
                .padding(.top, Space.s)
                CategoryBar(Self.filters, selection: kind)
                    .padding(.horizontal, -Space.pageMargin)
                    .padding(.vertical, Space.xs)
                content
            }
            .padding(.horizontal, Space.pageMargin)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.l)
        }
        .scrollIndicators(.hidden)
        .background(Color(role: .bgCanvas, in: theme))
        .refreshable { await store.load() }
        .swipesBack(perform: back)
        .task { await store.load() }
        .accessibilityIdentifier("wall.page")
    }

    @ViewBuilder private var content: some View {
        let months = store.months
        if months.isEmpty {
            switch store.phase {
            case .current: EmptyWall(kind: store.kind, checkIn: checkIn)
            case .offline: WallOffline { Task { await store.load() } }
            case .loading, .signedOut: EmptyView()
            }
        } else {
            ForEach(months) { month in
                Section {
                    LazyVGrid(columns: Self.columns, spacing: Self.gap) {
                        ForEach(month.posts) { post in
                            if let open {
                                Button {
                                    open(post)
                                } label: {
                                    PostTile(store: store, post: post)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("wall.tile")
                            } else {
                                PostTile(store: store, post: post).accessibilityIdentifier("wall.tile")
                            }
                        }
                    }
                } header: {
                    HStack(alignment: .firstTextBaseline) {
                        SectionLabel(month.title)
                        Spacer()
                        Text("\(month.posts.count) 张", bundle: .module)
                            .typeStyle(TypeRamp.footnote)
                            .foregroundStyle(Color(role: .fgMuted, in: theme))
                            .monospacedDigit()
                    }
                    .padding(.top, month.id == months.first?.id ? 0 : Space.m)
                }
            }
            if store.hasMore {
                Color.clear
                    .frame(height: Space.xxl)
                    .task(id: store.posts.last?.id) { await store.loadMore() }
            }
        }
    }

    /// The gap between tiles, which reads as one wall.
    private static let gap = Space.xxs
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: gap), count: 3)

    /// The filter: every kind, then each one.
    private enum Filter: Hashable {
        case all
        case only(PostKind)
    }

    private static let filters: [CategoryBarItem<Filter>] =
        [CategoryBarItem(id: .all, title: Text("全部", bundle: .module), accessibilityIdentifier: "wall.filter.all")]
        + PostKind.allCases.map {
            CategoryBarItem(
                id: .only($0), title: $0.chipName, accessibilityIdentifier: "wall.filter.\($0.rawValue)")
        }

    private var kind: Binding<Filter> {
        Binding {
            store.kind.map(Filter.only) ?? .all
        } set: { filter in
            let kind: PostKind? =
                switch filter {
                case .all: nil
                case .only(let kind): kind
                }
            Task { await store.show(kind) }
        }
    }
}

extension PostKind {
    /// The filter chip's name: the word the tiles carry in their corner.
    var chipName: Text {
        switch self {
        case .trained: Text("练了", bundle: .module)
        case .healthyMeal: Text("健康餐", bundle: .module)
        case .cheatMeal: Text("放纵餐", bundle: .module)
        case .disclaimer: Text("请假条", bundle: .module)
        }
    }
}

extension WallMonth {
    /// 2026年10月, October 2026.
    var title: Text {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let date = calendar.date(from: DateComponents(year: year, month: month, day: 15)) ?? .distantPast
        var style = Date.FormatStyle.dateTime.year().month(.wide)
        style.timeZone = .gmt
        style.locale = AppLanguage.current.locale
        return Text(date, format: style)
    }
}

/// No posts of the kind shown: the first one starts today; a kind with none says so.
private struct EmptyWall: View {
    @Environment(\.sceneTheme) private var theme
    let kind: PostKind?
    let checkIn: () -> Void

    var body: some View {
        VStack(spacing: Space.m) {
            if kind == nil {
                Text("第一条动态，从今天开始", bundle: .module)
                    .typeStyle(TypeRamp.headline)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                Button(action: checkIn) {
                    Label {
                        Text("去打卡", bundle: .module)
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(.regular))
                .accessibilityIdentifier("wall.checkIn")
            } else {
                Text("这一类还没发过", bundle: .module)
                    .typeStyle(TypeRamp.callout)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.xxl)
        .accessibilityIdentifier("wall.empty")
    }
}

/// The first load didn't reach the server: say so plainly, with a way to try again.
private struct WallOffline: View {
    @Environment(\.sceneTheme) private var theme
    let retry: () -> Void

    var body: some View {
        VStack(spacing: Space.s) {
            Text("网络开小差了", bundle: .module)
                .typeStyle(TypeRamp.callout)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
            Button(action: retry) { Text("再试一次", bundle: .module) }
                .buttonStyle(SecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.xxl)
        .accessibilityIdentifier("wall.offline")
    }
}
#endif
