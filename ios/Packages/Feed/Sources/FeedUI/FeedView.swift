#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SwiftUI

/// The 动态 tab: the squad's posts by day, newest first, each a card with the author's character
/// and the teammates' emoji (the approved feed, version 20). The app's tab bar floats over it;
/// the safe area the app gives it already leaves room. Pull to load again; the end loads the
/// week before.
public struct FeedView: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: FeedModel
    /// Opens 今天 to check in, from the empty feed.
    private let checkIn: () -> Void

    /// The coordinate space the emoji bar is placed in: the whole tab.
    static let space = "feed"

    public init(model: FeedModel, checkIn: @escaping () -> Void) {
        _model = State(initialValue: model)
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
                    content
                }
                .padding(.horizontal, Space.pageMargin)
                .padding(.top, Space.l)
                .padding(.bottom, Space.l)
            }
            .scrollDismissesKeyboard(.immediately)
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
        .coordinateSpace(.named(Self.space))
        .overlay { EmojiBarLayer(model: model) }
        .background(Color(role: .bgCanvas, in: theme))
        .haptic(.reaction, trigger: model.responses)
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
        case .date(let day): Text(Self.noon(of: day).formatted(Self.dayStyle))
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
