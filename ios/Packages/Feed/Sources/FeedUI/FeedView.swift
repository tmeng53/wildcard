#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SwiftUI

/// The 动态 tab: the squad's posts by day, newest first, each a card with the author's character
/// and the teammates' emoji (the approved feed, version 20, with the approved reaction bar). The app's tab bar floats over it;
/// the safe area the app gives it already leaves room. Pull to load again; the end loads the
/// week before. A card's comments or comment button opens its own page (`PostDetailView`).
public struct FeedView: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: FeedModel
    /// The post at the top of the list, set to open 动态 on one.
    @State private var position: CheckInID?
    /// Opens 今天 to check in, from the empty feed.
    private let checkIn: () -> Void
    /// What the app shows under the title, before the posts: the squad's latest 战报.
    private let header: AnyView?

    /// The feed's coordinate space: where the emoji bar is, where a finger slides and where emoji
    /// fly.
    static let space = "feed"

    public init(model: FeedModel, header: AnyView? = nil, checkIn: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.header = header
        self.checkIn = checkIn
    }

    public var body: some View {
        // A post's own page slides in over the feed, which keeps its place underneath.
        ZStack {
            feed
                .allowsHitTesting(model.opened == nil)
                .accessibilityHidden(model.opened != nil)
            if let opened = model.opened {
                PostDetailView(model: model, post: opened) {
                    withAnimation(.wildcard(Motion.page, reduceMotion: reduceMotion)) { model.opened = nil }
                }
                .transition(.move(edge: .trailing))
            }
        }
    }

    private var feed: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.m) {
                Text("动态", bundle: .module)
                    .typeStyle(TypeRamp.largeTitle)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("feed.title")
                    .blur(radius: model.lifted ? Scrim.blurRadius : 0)
                header
                content
            }
            .scrollTargetLayout()
            .padding(.horizontal, Space.pageMargin)
            .padding(.top, Space.l)
            .padding(.bottom, Space.l)
        }
        // Keeps a focused post at the top while what is above it loads and grows (the 战报's
        // tile, the posts the server lists), which a one-off scroll would lose.
        .scrollPosition(id: $position, anchor: .top)
        .scrollDismissesKeyboard(.immediately)
        // A held card's slide picks an emoji; the list stays put under it.
        .scrollDisabled(model.lifted)
        .refreshable { await model.load() }
        .onChange(of: model.focus, initial: true) { _, focus in
            guard let focus else { return }
            withAnimation(.wildcard(Motion.page, reduceMotion: reduceMotion)) { position = focus }
            model.focus = nil
        }
        .feedSurface(model, isActive: model.opened == nil)
        .task { await model.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.load() } }
        }
    }

    @ViewBuilder private var content: some View {
        let sections = model.store.sections
        if sections.isEmpty {
            // Only a squad the server says never posted is empty; offline, pull to try again.
            if model.store.phase == .current {
                EmptyFeed(model: model, checkIn: checkIn)
            }
        } else {
            ForEach(sections) { section in
                Section {
                    ForEach(section.posts) { post in
                        PostCard(model: model, post: post)
                            .id(post.id)
                    }
                } header: {
                    SectionLabel(section.heading.title)
                        .padding(.top, section.id == sections.first?.id ? 0 : Space.xs)
                        .blur(radius: model.lifted ? Scrim.blurRadius : 0)
                }
            }
            if model.store.hasEarlier {
                Color.clear
                    .frame(height: Space.xxl)
                    .task(id: sections.last?.id) { await model.store.loadEarlier() }
            }
        }
    }
}

extension DayHeading {
    /// 今天, 昨天, 周三, or 10月14日.
    var title: Text {
        switch self {
        case .today: Text("今天", bundle: .module)
        case .yesterday: Text("昨天", bundle: .module)
        case .weekday(1): Text("周一", bundle: .module)
        case .weekday(2): Text("周二", bundle: .module)
        case .weekday(3): Text("周三", bundle: .module)
        case .weekday(4): Text("周四", bundle: .module)
        case .weekday(5): Text("周五", bundle: .module)
        case .weekday(6): Text("周六", bundle: .module)
        case .weekday: Text("周日", bundle: .module)
        case .date(let day): Text(Self.noon(of: day), format: Self.dayStyle)
        }
    }

    /// 10月14日, Oct 14: the month and day in UTC, where `noon(of:)` puts the day.
    private static let dayStyle: Date.FormatStyle = {
        var style = Date.FormatStyle.dateTime.month().day()
        style.timeZone = .gmt
        return style
    }()

    /// The day as a date to format, at noon UTC.
    private static func noon(of day: LocalDay) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let components = DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)
        return calendar.date(from: components) ?? .distantPast
    }
}
#endif
