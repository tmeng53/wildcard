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
    /// With the sport's icon (the same one the planned day showed) and a small check, or a bare
    /// check without one.
    case trained(symbol: String?)
    /// A 请假条: light grey with 假, like a rest day (grey days weren't trained); it counts as
    /// checked in.
    case excused
    /// A rest day in the plan: light grey with a moon.
    case restDay
    /// A training day not done (yet, or missed): a thin grey ring, never red.
    case open
    /// A training day not done yet with its sport's icon, in the scene's color, in the ring.
    case planned(symbol: String)
}

/// What one day of my week shows under the calendar once it is picked. No calories or body numbers.
public struct WeekDayDetail: Sendable, Hashable {
    /// A day's 健康餐 and 放纵餐.
    public struct Meals: Sendable, Hashable {
        public let healthy: Int
        public let cheat: Int

        public init(healthy: Int, cheat: Int) {
            self.healthy = healthy
            self.cheat = cheat
        }
    }

    /// What the day holds, as the app words it: 跑步 32 分钟, 休息日, 请假了, or the plan's sport.
    public let line: String
    /// The line is the plan's sport, not yet done: drawn light.
    public let isPlan: Bool
    /// Nil for a day still to come, which shows no meals.
    public let meals: Meals?

    public init(line: String, isPlan: Bool, meals: Meals?) {
        self.line = line
        self.isPlan = isPlan
        self.meals = meals
    }
}

/// My week: what I trained, my count against my plan, and Monday to Sunday, each day with what it
/// holds. No calories or body numbers.
public struct MyWeek: Sendable, Hashable {
    /// What I trained this week, as the app words it (游泳 1 · 跑步 1).
    public let summary: String
    public let done: Int
    public let planned: Int
    /// Monday first, seven days.
    public let days: [WeekDayStatus]
    /// Today's index in `days`, if this is the current week.
    public let today: Int?
    /// Monday first, seven days: what each day shows once picked; empty for a week whose days
    /// can't be picked.
    public let details: [WeekDayDetail]

    public init(
        summary: String, done: Int, planned: Int, days: [WeekDayStatus], today: Int?, details: [WeekDayDetail]
    ) {
        self.summary = summary
        self.done = done
        self.planned = planned
        self.days = days
        self.today = today
        self.details = details
    }
}

/// The squad card's two pages.
public enum SquadCardPage: Int, CaseIterable, Sendable, Hashable {
    case squad
    case mine
}

/// The card on the home scene, swiped between two pages of the same height: the squad's week
/// (score, bar, everyone's rings in one row) and my week (my count, Monday to Sunday, and the
/// picked day's line: what I trained and my meals; tapping a day picks it, today until then).
/// One white card straight on the scene, no shadow: a swipe moves only what is inside it, and two
/// dots at its foot say which page shows; tapping one goes there. The caller keeps `page`, so the card reopens on
/// the page it was left on, and `pickedDay` (an index in `MyWeek.days`; nil for today). A
/// `footer` (the evening's 今日赛况 tag) is the squad page's last row;
/// the page keeps its height by drawing its rows closer.
public struct SquadCard<Avatar: View, Footer: View>: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let squad: SquadWeek
    private let mine: MyWeek
    @Binding private var page: SquadCardPage
    @Binding private var pickedDay: Int?
    private let avatar: (SquadMember) -> Avatar
    private let footer: Footer?

    public init(
        squad: SquadWeek, mine: MyWeek, page: Binding<SquadCardPage>, pickedDay: Binding<Int?> = .constant(nil),
        @ViewBuilder avatar: @escaping (SquadMember) -> Avatar, @ViewBuilder footer: () -> Footer
    ) {
        self.squad = squad
        self.mine = mine
        _page = page
        _pickedDay = pickedDay
        self.avatar = avatar
        self.footer = footer()
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    SquadPage(squad: squad, avatar: avatar, footer: footer)
                        .pageFrame()
                        .id(SquadCardPage.squad)
                    MyWeekPage(mine: mine, pickedDay: $pickedDay)
                        .pageFrame()
                        .id(SquadCardPage.mine)
                }
                // Both pages as tall as the taller one.
                .fixedSize(horizontal: false, vertical: true)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: pagePosition)
            .scrollIndicators(.hidden)
            PageDots(page: $page)
                .padding(.bottom, Space.xs)
        }
        .background(Color(role: .bgCanvas, in: theme))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .padding(.horizontal, Space.pageMargin)
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
        squad: SquadWeek, mine: MyWeek, page: Binding<SquadCardPage>, pickedDay: Binding<Int?> = .constant(nil),
        @ViewBuilder avatar: @escaping (SquadMember) -> Avatar
    ) {
        self.squad = squad
        self.mine = mine
        _page = page
        _pickedDay = pickedDay
        self.avatar = avatar
        footer = nil
    }
}

extension View {
    /// A page of the squad card: the card's whole width, the same height on both pages, with
    /// the card's padding except at its foot, where the dots sit.
    fileprivate func pageFrame() -> some View {
        frame(
            maxWidth: .infinity, minHeight: SquadCardMetrics.pageContent, maxHeight: .infinity, alignment: .topLeading
        )
        .padding([.top, .horizontal], Space.cardPadding)
        .padding(.bottom, Space.xs)
        .containerRelativeFrame(.horizontal)
    }
}

/// Sizes that belong to the squad card alone.
enum SquadCardMetrics {
    /// Inside each page's padding: 186 tall with the card's padding, on both pages; the dots'
    /// row adds its own height under them.
    static let pageContent: Double = 186 - 2 * Space.cardPadding
    /// Between rings: eight 38-point rings fit a 358-point card.
    static let ringSpacing: Double = 3
    /// On a narrower phone (375 points), eight rings shrink to fit: 32-point rings, 1 apart.
    static let compactAvatar: Double = Sizing.characterHead - 6
    static let compactRingSpacing: Double = 1
    /// The second page's day circles.
    static let day: Double = 30
    static let dayGlyph: Double = 14
    static let badge: Double = 13
    static let badgeGlyph: Double = 7
    /// Today's circle is drawn in ink, a little heavier than a planned day's hairline ring.
    static let todayStroke: Double = 2
    /// The picked day's capsule behind its name.
    static let pick: Double = 20
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
    @Binding var pickedDay: Int?

    var body: some View {
        let picked = shownDay
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                label: Text("本周我的训练", bundle: .module), title: mine.summary, count: mine.done, goal: mine.planned)
            Spacer(minLength: Space.s)
            HStack(spacing: 0) {
                ForEach(Array(mine.days.enumerated()), id: \.offset) { index, status in
                    Button {
                        pickedDay = index
                    } label: {
                        DayCircle(
                            status: status, isToday: index == mine.today, isPicked: index == picked, weekday: index
                        )
                        .frame(width: Sizing.minimumTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // A week without details (the 上场 card's) has no day to pick.
                    .disabled(mine.details.isEmpty)
                    .accessibilityAddTraits(index == picked ? .isSelected : [])
                    .accessibilityIdentifier("squadcard.day.\(index)")
                    if index < mine.days.count - 1 { Spacer(minLength: 0) }
                }
            }
            // The circles line up with the card's padding, their tap areas reaching past it.
            .padding(.horizontal, (SquadCardMetrics.day - Sizing.minimumTapTarget) / 2)
            Spacer(minLength: Space.s)
            if mine.details.indices.contains(picked) {
                DayLine(detail: mine.details[picked], weekday: picked, isToday: picked == mine.today)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The picked day: today until one is tapped.
    private var shownDay: Int { pickedDay ?? mine.today ?? 0 }
}

/// Two dots at the card's foot, the current page's solid. Tapping one goes to it.
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
                        // 6 apart to the eye, in a row as tall as the card's padding, each
                        // still a full tap target tall.
                        .frame(width: SquadCardMetrics.dot * 2, height: Space.cardPadding)
                        .contentShape(Rectangle().inset(by: -(Sizing.minimumTapTarget - Space.cardPadding) / 2))
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
