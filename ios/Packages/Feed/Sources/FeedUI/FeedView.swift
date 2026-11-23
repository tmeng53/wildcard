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
/// week before. A card's comments or comment button opens its own page (`PostDetailView`), which the app
/// pushes.
public struct FeedView: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: FeedModel
    /// The post the list holds at its top: the one opened from the home or just edited, then
    /// whichever the member scrolls to. The system's scroll position keeps it there while what is
    /// above it (the 战报's tile, the posts the server lists, cards the lazy list measures only
    /// when drawn) arrives; a hand-made pin that scrolled back on every height change chased the
    /// lazy list's own measuring and froze the app (#924).
    @State private var position: CheckInID?
    /// Opens 今天 to check in, from the empty feed.
    private let checkIn: () -> Void
    /// What the app shows under the title, before the posts: the squad's latest 战报.
    private let header: AnyView?
    /// What the app shows at the title's right: the bell (通知).
    private let accessory: AnyView?

    /// The feed's coordinate space: where the emoji bar is, where a finger slides and where emoji
    /// fly.
    static let space = "feed"

    public init(model: FeedModel, header: AnyView? = nil, accessory: AnyView? = nil, checkIn: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.header = header
        self.accessory = accessory
        self.checkIn = checkIn
    }

    /// The root of 动态's NavigationStack. A card's comments set the model's `opened`, and the
    /// app pushes that post's page (`PostDetailView`) on the stack's own path, so every page over
    /// 动态 goes the one way and the feed keeps its place underneath.
    public var body: some View {
        feed
    }

    private var feed: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .center, spacing: Space.s) {
                    Text(copy: "动态", bundle: .module)
                        .typeStyle(TypeRamp.largeTitle)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("feed.title")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    accessory
                }
                .blur(radius: model.lifted ? Scrim.blurRadius : 0)
                header
                content
            }
            .scrollTargetLayout()
            .padding(.horizontal, Space.pageMargin)
            .padding(.top, Space.l)
            .padding(.bottom, Space.l)
        }
        .scrollPosition(id: $position, anchor: .top)
        .scrollDismissesKeyboard(.immediately)
        // A held card's slide picks an emoji; the list stays put under it.
        .scrollDisabled(model.lifted)
        .refreshable { await model.load() }
        .task(id: model.focus) {
            guard let focus = model.focus else { return }
            // Waits a frame, so the list has the post before scrolling to it: opened from the
            // home, it hasn't yet.
            await Task.yield()
            withAnimation(.wildcard(Motion.page, reduceMotion: reduceMotion)) {
                position = focus
            }
            model.focus = nil
        }
        .feedSurface(model, isActive: model.opened == nil)
        .managesPosts(model, isActive: model.opened == nil)
        // Opened before any post was read: the tickets rock until the list arrives.
        .loadingCover(model.store.phase == .loading && model.store.sections.isEmpty) {
            TicketSpinner(on: .light(.bgCanvas))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(role: .bgCanvas, in: theme))
        }
        .task { await model.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.load() } }
        }
    }

    @ViewBuilder private var content: some View {
        let sections = model.store.sections
        if sections.isEmpty {
            // Only a squad the server says never posted is empty; offline, nothing was ever read,
            // so say so, with a way to try again (pulling down tries again too).
            switch model.store.phase {
            case .current:
                EmptyFeed(model: model, checkIn: checkIn)
            case .offline:
                StateView.offline(retryIdentifier: "feed.retry") { Task { await model.load() } }
                    .padding(.top, Space.xxl)
            case .loading, .notInSquad, .signedOut:
                EmptyView()
            }
        } else {
            // 战术板 tops today, even before anyone posted today (a squad that never posted
            // shows its empty scene instead). Its day is the squad's, as on the home's sideline.
            if let note = model.coachNote, sections.first?.heading != .today {
                SectionLabel(DayHeading.today.title)
                    .blur(radius: model.lifted ? Scrim.blurRadius : 0)
                CoachBoard(note: note)
                    .blur(radius: model.lifted ? Scrim.blurRadius : 0)
            }
            ForEach(sections) { section in
                Section {
                    if section.heading == .today, let note = model.coachNote {
                        CoachBoard(note: note)
                            .blur(radius: model.lifted ? Scrim.blurRadius : 0)
                    }
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
                // Shown, it reads the week before; the dots say so once the wait lasts, and go
                // when it ends, answered or not.
                ZStack {
                    if model.store.isLoadingEarlier {
                        LoadingDots().foregroundStyle(Color(role: .fgDefault, in: theme))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: Space.xxl)
                .task(id: sections.last?.id) { await model.loadEarlier() }
            }
        }
    }
}

extension DayHeading {
    /// 今天, 昨天, 周三, or 10月14日, as 动态's days and a place's posts say them.
    public var title: Text {
        switch self {
        case .today: Text(copy: "今天", bundle: .module)
        case .yesterday: Text(copy: "昨天", bundle: .module)
        case .weekday(1): Text(copy: "周一", bundle: .module)
        case .weekday(2): Text(copy: "周二", bundle: .module)
        case .weekday(3): Text(copy: "周三", bundle: .module)
        case .weekday(4): Text(copy: "周四", bundle: .module)
        case .weekday(5): Text(copy: "周五", bundle: .module)
        case .weekday(6): Text(copy: "周六", bundle: .module)
        case .weekday: Text(copy: "周日", bundle: .module)
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
