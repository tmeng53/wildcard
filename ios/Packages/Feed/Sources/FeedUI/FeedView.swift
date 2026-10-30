#if os(iOS)
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SwiftUI

/// The 动态 tab: the squad's posts by day, newest first, each a card with the author's character
/// and the teammates' emoji (the approved feed, version 20, with the approved reaction bar). The app's tab bar floats over it;
/// the safe area the app gives it already leaves room. Pull to load again; the end loads the
/// week before.
public struct FeedView: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: FeedModel
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
        ScrollViewReader { scroller in
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
                .padding(.horizontal, Space.pageMargin)
                .padding(.top, Space.l)
                .padding(.bottom, Space.l)
            }
            .scrollDismissesKeyboard(.immediately)
            // A held card's slide picks an emoji; the list stays put under it.
            .scrollDisabled(model.lifted)
            .refreshable { await model.load() }
            .onChange(of: model.focus) { _, focus in
                guard let focus else { return }
                withAnimation(.wildcard(Motion.page, reduceMotion: reduceMotion)) {
                    scroller.scrollTo(focus, anchor: .top)
                }
                model.focus = nil
            }
            .onAppear {
                // Opened from the home before the list was drawn.
                if let focus = model.focus {
                    scroller.scrollTo(focus, anchor: .top)
                    model.focus = nil
                }
            }
        }
        .overlayPreferenceValue(FeedAnchors.self) { anchors in
            FeedLayer(model: model, bar: anchors.bar, who: anchors.who, heads: anchors.heads)
        }
        .coordinateSpace(.named(Self.space))
        .background(Color(role: .bgCanvas, in: theme))
        // Opened before any post was read: the character jogs in place until the list arrives.
        .loadingCover(model.store.phase == .loading && model.store.sections.isEmpty) {
            LoadingCharacter()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(role: .bgCanvas, in: theme))
        }
        // A brand screen: buttons and selection wear the brand; only the kind tags keep the scene.
        .accentTone(.brand)
        .haptic(.pick, trigger: model.picks)
        .haptic(.appear, trigger: model.lifts)
        .haptic(.reaction, trigger: model.arrivals)
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
                // Shown, it reads the week before; the dots say so once the wait lasts.
                LoadingDots()
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .frame(maxWidth: .infinity, minHeight: Space.xxl)
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
