#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// One teammate's place in a squad card's row.
public struct SquadMember: Identifiable, Sendable, Hashable {
    public let id: String
    public let status: RingStatus
    /// The person holding the phone: only their ring plays haptics as it closes.
    public let isMe: Bool
    /// Names the member's ring for UI tests.
    public let accessibilityIdentifier: String?

    public init(id: String, status: RingStatus, isMe: Bool = false, accessibilityIdentifier: String? = nil) {
        self.id = id
        self.status = status
        self.isMe = isMe
        self.accessibilityIdentifier = accessibilityIdentifier
    }
}

/// The squad's week: its name, check-ins against the week's planned training days, and everyone.
public struct SquadWeek: Sendable, Hashable {
    public let name: String
    public let done: Int
    public let goal: Int
    /// Up to 8, checked in first by time, then resting, then everyone else.
    public let members: [SquadMember]

    public init(name: String, done: Int, goal: Int, members: [SquadMember]) {
        self.name = name
        self.done = done
        self.goal = goal
        self.members = members
    }
}

/// How one day of my week stands, as the second page's calendar draws it.
public enum WeekDayStatus: Sendable, Hashable {
    /// 练了: the scene's color with a check.
    case trained
    /// A 请假条: the scene's color with 假; it counts as checked in.
    case excused
    /// A rest day in the plan: light grey with a moon.
    case restDay
    /// A training day not done (yet, or missed): a thin grey ring, never red.
    case open
}

/// My week: what I trained, my count against my plan, Monday to Sunday, and counts that only go
/// up. No calories or body numbers.
public struct MyWeek: Sendable, Hashable {
    /// What I trained this week, as the app words it (游泳 1 · 跑步 1).
    public let summary: String
    public let done: Int
    public let planned: Int
    /// Monday first, seven days.
    public let days: [WeekDayStatus]
    /// Today's index in `days`, if this is the current week.
    public let today: Int?
    public let healthyMeals: Int
    public let cheatMeals: Int
    /// Every 练了 since joining.
    public let lifetimeTrained: Int

    public init(
        summary: String, done: Int, planned: Int, days: [WeekDayStatus], today: Int?, healthyMeals: Int,
        cheatMeals: Int, lifetimeTrained: Int
    ) {
        self.summary = summary
        self.done = done
        self.planned = planned
        self.days = days
        self.today = today
        self.healthyMeals = healthyMeals
        self.cheatMeals = cheatMeals
        self.lifetimeTrained = lifetimeTrained
    }
}

/// The squad card's two pages.
public enum SquadCardPage: Int, CaseIterable, Sendable, Hashable {
    case squad
    case mine
}

/// The card on the home scene, swiped between two pages of the same height: the squad's week
/// (score, bar, everyone's rings in one row) and my week (my count, Monday to Sunday, counts).
/// White cards straight on the scene, no shadow, 12 apart while swiping; two dots under them say
/// which page shows, and tapping one goes there. The caller keeps `page`, so the card reopens on
/// the page it was left on. A `footer` (the evening's 今日赛况 tag) is the squad page's last row;
/// the page keeps its height by drawing its rows closer.
public struct SquadCard<Avatar: View, Footer: View>: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let squad: SquadWeek
    private let mine: MyWeek
    @Binding private var page: SquadCardPage
    private let avatar: (SquadMember) -> Avatar
    private let footer: Footer?

    public init(
        squad: SquadWeek, mine: MyWeek, page: Binding<SquadCardPage>,
        @ViewBuilder avatar: @escaping (SquadMember) -> Avatar, @ViewBuilder footer: () -> Footer
    ) {
        self.squad = squad
        self.mine = mine
        _page = page
        self.avatar = avatar
        self.footer = footer()
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: Space.s) {
                    SquadPage(squad: squad, avatar: avatar, footer: footer)
                        .pageFrame()
                        .id(SquadCardPage.squad)
                    MyWeekPage(mine: mine)
                        .pageFrame()
                        .id(SquadCardPage.mine)
                }
                // Both pages as tall as the taller one.
                .fixedSize(horizontal: false, vertical: true)
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, Space.pageMargin, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: pagePosition)
            .scrollIndicators(.hidden)
            PageDots(page: $page)
        }
        .accessibilityElement(children: .contain)
    }

    /// The scroll position as a page; nil while between pages, which leaves `page` as it was.
    private var pagePosition: Binding<SquadCardPage?> {
        Binding {
            page
        } set: { newPage in
            if let newPage { page = newPage }
        }
    }
}

extension SquadCard where Footer == EmptyView {
    public init(
        squad: SquadWeek, mine: MyWeek, page: Binding<SquadCardPage>,
        @ViewBuilder avatar: @escaping (SquadMember) -> Avatar
    ) {
        self.squad = squad
        self.mine = mine
        _page = page
        self.avatar = avatar
        footer = nil
    }
}

extension View {
    /// A page of the squad card: a full-width white card, the same height on both pages.
    fileprivate func pageFrame() -> some View {
        frame(
            maxWidth: .infinity, minHeight: SquadCardMetrics.pageContent, maxHeight: .infinity, alignment: .topLeading
        )
        .card(on: .scene)
        .containerRelativeFrame(.horizontal)
    }
}

/// Sizes that belong to the squad card alone.
private enum SquadCardMetrics {
    /// Inside each page's padding: 186 tall in all, on both pages.
    static let pageContent: Double = 186 - 2 * Space.cardPadding
    /// Between rings: eight 38-point rings fit a 358-point card.
    static let ringSpacing: Double = 3
    /// On a narrower phone (375 points), eight rings shrink to fit: 32-point rings, 1 apart.
    static let compactAvatar: Double = Sizing.characterHead - 6
    static let compactRingSpacing: Double = 1
    /// The second page's day circles.
    static let day: Double = 30
    static let dayGlyph: Double = 14
    /// Today's circle is drawn in ink, a little heavier than a planned day's hairline ring.
    static let todayStroke: Double = 2
    static let dot: Double = 6
}

/// A big number with its label and title on the left, as both pages open.
private struct PageHeader: View {
    @Environment(\.sceneTheme) private var theme
    let label: Text
    let title: String
    let count: Int
    let goal: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: Space.s) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                SectionLabel(label)
                Text(verbatim: title)
                    .typeStyle(TypeRamp.headline)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Score(count: count, goal: goal, size: .hero)
        }
    }
}

private struct SquadPage<Avatar: View, Footer: View>: View {
    let squad: SquadWeek
    let avatar: (SquadMember) -> Avatar
    let footer: Footer?

    var body: some View {
        // With a footer the rows sit 8 apart instead of 12, so the page stays 186 tall.
        let gap = footer == nil ? Space.s : Space.xs
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                label: Text("本周小队训练", bundle: .module), title: squad.name, count: squad.done, goal: squad.goal)
            Spacer(minLength: gap)
            ProgressBar(fraction: squad.goal > 0 ? Double(squad.done) / Double(squad.goal) : 0)
            Spacer(minLength: gap)
            ViewThatFits(in: .horizontal) {
                rings(avatarSize: Sizing.characterHead, spacing: SquadCardMetrics.ringSpacing)
                rings(avatarSize: SquadCardMetrics.compactAvatar, spacing: SquadCardMetrics.compactRingSpacing)
            }
            if let footer {
                Spacer(minLength: gap)
                footer
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func rings(avatarSize: Double, spacing: Double) -> some View {
        HStack(spacing: spacing) {
            ForEach(squad.members) { member in
                StatusRing(status: member.status, avatarSize: avatarSize, playsHaptics: member.isMe) { avatar(member) }
                    .accessibilityIdentifier(ifPresent: member.accessibilityIdentifier)
            }
        }
    }
}

private struct MyWeekPage: View {
    @Environment(\.sceneTheme) private var theme
    let mine: MyWeek

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                label: Text("本周我的训练", bundle: .module), title: mine.summary, count: mine.done, goal: mine.planned)
            Spacer(minLength: Space.s)
            HStack(spacing: 0) {
                ForEach(Array(mine.days.enumerated()), id: \.offset) { index, status in
                    DayCircle(status: status, isToday: index == mine.today, weekday: index)
                    if index < mine.days.count - 1 { Spacer(minLength: 0) }
                }
            }
            Spacer(minLength: Space.s)
            HStack(spacing: Space.m) {
                Count(label: Text("健康餐", bundle: .module), value: mine.healthyMeals)
                Count(label: Text("放纵餐", bundle: .module), value: mine.cheatMeals)
                Count(label: Text("累计练了", bundle: .module), value: mine.lifetimeTrained)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// One day: its circle over its name. Today's name is ink and heavier.
private struct DayCircle: View {
    @Environment(\.sceneTheme) private var theme
    let status: WeekDayStatus
    let isToday: Bool
    let weekday: Int

    var body: some View {
        VStack(spacing: Space.xxs) {
            circle
                .frame(width: SquadCardMetrics.day, height: SquadCardMetrics.day)
            Self.name(weekday)
                .typeStyle(isToday ? TypeRamp.tabSelected : TypeRamp.tab)
                .foregroundStyle(Color(role: isToday ? .fgDefault : .fgMuted, in: theme))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.name(weekday))
        .accessibilityValue(value)
    }

    @ViewBuilder private var circle: some View {
        switch status {
        case .trained:
            Image(systemName: "checkmark")
                .font(.system(size: SquadCardMetrics.dayGlyph, weight: .bold))
                .foregroundStyle(Color(role: .fgOnAccent, in: theme))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(role: .bgAccent, in: theme), in: Circle())
        case .excused:
            Text("假", bundle: .module)
                .typeStyle(TypeRamp.footnoteEmphasis)
                .foregroundStyle(Color(role: .fgOnAccent, in: theme))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(role: .bgAccent, in: theme), in: Circle())
        case .restDay:
            Image(systemName: "moon.fill")
                .font(.system(size: SquadCardMetrics.dayGlyph * 0.85))
                .foregroundStyle(Color(role: .fgSubtle, in: theme))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(role: .bgSubtle, in: theme), in: Circle())
        case .open:
            Circle()
                .strokeBorder(
                    Color(role: isToday ? .fgDefault : .borderDefault, in: theme),
                    lineWidth: isToday ? SquadCardMetrics.todayStroke : Sizing.selectionStroke)
        }
    }

    private var value: Text {
        switch status {
        case .trained: Text("练了", bundle: .module)
        case .excused: Text("请假", bundle: .module)
        case .restDay: Text("休息日", bundle: .module)
        case .open where isToday: Text("今天", bundle: .module)
        case .open: Text("还没练", bundle: .module)
        }
    }

    static func name(_ weekday: Int) -> Text {
        switch weekday {
        case 0: Text("一", bundle: .module)
        case 1: Text("二", bundle: .module)
        case 2: Text("三", bundle: .module)
        case 3: Text("四", bundle: .module)
        case 4: Text("五", bundle: .module)
        case 5: Text("六", bundle: .module)
        default: Text("日", bundle: .module)
        }
    }
}

/// A count beside its label: 健康餐 3.
private struct Count: View {
    @Environment(\.sceneTheme) private var theme
    let label: Text
    let value: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
            label
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
            Score(count: value, size: .small)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Two dots under the card, the current page's solid. Tapping one goes to it.
private struct PageDots: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var page: SquadCardPage

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SquadCardPage.allCases, id: \.self) { item in
                Button {
                    withAnimation(.wildcard(Motion.page, reduceMotion: reduceMotion)) { page = item }
                } label: {
                    Circle()
                        .fill(Color(role: .fgOnScene, in: theme).opacity(item == page ? 1 : 0.25))
                        .frame(width: SquadCardMetrics.dot, height: SquadCardMetrics.dot)
                        // 6 apart to the eye; each answers taps 44 tall.
                        .frame(width: SquadCardMetrics.dot * 2, height: Sizing.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item == .squad ? Text("小队", bundle: .module) : Text("我这周", bundle: .module))
                .accessibilityAddTraits(item == page ? .isSelected : [])
                .accessibilityIdentifier("squadcard.page.\(item == .squad ? "squad" : "mine")")
            }
        }
        .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: page)
    }
}
#endif
