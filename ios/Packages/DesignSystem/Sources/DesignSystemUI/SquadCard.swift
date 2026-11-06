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

/// The squad's week: its name, the days anyone trained against its goal (人均 N 天 times its
/// members), and everyone's today.
public struct SquadWeek: Sendable, Hashable {
    public let name: String
    public let done: Int
    public let goal: Int
    /// The goal its captain set, 人均 N 天.
    public let daysPerMember: Int
    /// Up to 8, checked in first by time, then resting, then everyone else.
    public let members: [SquadMember]

    public init(name: String, done: Int, goal: Int, daysPerMember: Int = 3, members: [SquadMember]) {
        self.name = name
        self.done = done
        self.goal = goal
        self.daysPerMember = daysPerMember
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
/// One card of scene glass straight on the scene, no shadow: a swipe moves only what is inside it,
/// and two dots at its foot say which page shows; tapping one goes there. Given `collapses`, a
/// grabber under the dots, or a swipe up, folds it into `SquadCapsule`. The caller keeps `page`,
/// so the card reopens showing the page it was left on, and `pickedDay` (an index in
/// `MyWeek.days`; nil for today). A `footer` (the evening's 今日赛况 tag) is the squad page's last
/// row; the page keeps its height by drawing its rows closer.
public struct SquadCard<Avatar: View, Footer: View>: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let squad: SquadWeek
    private let mine: MyWeek
    @Binding private var page: SquadCardPage
    @Binding private var pickedDay: Int?
    private let avatar: (SquadMember) -> Avatar
    private let footer: Footer?
    private var openSquad: (() -> Void)?
    private var collapse: (() -> Void)?
    private var morph: GlassMorph?
    /// How far a swipe up has lifted the card, while the finger is down.
    @State private var lift = 0.0

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
        let anchor: UnitPoint = page == .squad ? .leading : .trailing
        VStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    SquadPage(squad: squad, avatar: avatar, footer: footer, openSquad: openSquad)
                        .squadCardPage()
                        .id(SquadCardPage.squad)
                    MyWeekPage(mine: mine, pickedDay: $pickedDay)
                        .squadCardPage()
                        .id(SquadCardPage.mine)
                }
                .fixedSize(horizontal: false, vertical: true)  // Both pages as tall as the taller.
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: pagePosition)
            .defaultScrollAnchor(anchor, for: .initialOffset)  // Reopened, it shows `page`,
            .defaultScrollAnchor(anchor, for: .sizeChanges)  // also while its glass grows.
            .scrollIndicators(.hidden)
            PageDots(page: $page)
                .padding(.bottom, Space.xs).zIndex(1)  // Over the grabber's tap area, which reaches up here.
            if let collapse {
                Grabber(label: Text("收起小队卡片", bundle: .module), action: collapse)
                    .padding(.bottom, Space.xs)
                    .accessibilityIdentifier("squadcard.collapse")
            }
        }
        .clipShape(shape)
        .sceneGlass(in: shape, theme: theme, morph: morph)
        .offset(y: lift)
        .simultaneousGesture(foldUp, including: collapse == nil ? .subviews : .all)
        .padding(.horizontal, Space.pageMargin)
        .accessibilityElement(children: .contain)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
    }

    /// A swipe up lifts the card a little against the finger and, past `SquadCardMetrics.fold`,
    /// folds it; sideways swipes stay the pages'.
    private var foldUp: some Gesture {
        DragGesture(minimumDistance: SquadCardMetrics.dragStart)
            .onChanged { value in
                guard value.isVertical else { return }
                lift = min(0, value.translation.height) * SquadCardMetrics.rubber
            }
            .onEnded { value in
                let folds = value.isVertical && value.translation.height < -SquadCardMetrics.fold
                withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { lift = 0 }
                if folds { collapse?() }
            }
    }

    /// The squad's name gets a chevron and opens `action` (我的小队) when tapped.
    public func opensSquad(_ action: @escaping () -> Void) -> Self {
        var card = self
        card.openSquad = action
        return card
    }

    /// A grabber under the page dots, and a swipe up, fold the card; `action` folds it.
    public func collapses(_ action: @escaping () -> Void) -> Self {
        var card = self
        card.collapse = action
        return card
    }

    /// The card's glass morphs into the glass with the same id, its folded capsule.
    public func morphs(_ morph: GlassMorph) -> Self {
        var card = self
        card.morph = morph
        return card
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

/// A big number with its label and title on the left, as both pages open. Given `open`, the
/// title is a button with a chevron after it.
private struct PageHeader: View {
    @Environment(\.sceneTheme) private var theme
    let label: Text
    let title: String
    let count: Int
    let goal: Int
    /// A word after the score (天).
    var unit: Text?
    var open: (() -> Void)?

    var body: some View {
        HStack(alignment: .bottom, spacing: Space.s) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                SectionLabel(label)
                if let open {
                    Button(action: open) {
                        HStack(spacing: Space.xxs) {
                            titleText
                            Image(systemName: "chevron.right")
                                .font(.system(size: Sizing.smallIcon - 2, weight: .semibold))
                                .foregroundStyle(Color(role: .fgMuted, in: theme))
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityIdentifier("squadcard.squad")
                } else {
                    titleText
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
                Score(count: count, goal: goal, size: .hero)
                if let unit {
                    unit
                        .typeStyle(TypeRamp.denominator(of: TypeRamp.scoreHero))
                        .foregroundStyle(Color(role: .fgSubtle, in: theme))
                }
            }
        }
    }

    private var titleText: some View {
        Text(verbatim: title)
            .typeStyle(TypeRamp.headline)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .lineLimit(1)
    }
}

private struct SquadPage<Avatar: View, Footer: View>: View {
    let squad: SquadWeek
    let avatar: (SquadMember) -> Avatar
    let footer: Footer?
    let openSquad: (() -> Void)?

    var body: some View {
        // With a footer the rows sit 8 apart instead of 12, so the page stays 186 tall.
        let gap = footer == nil ? Space.s : Space.xs
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                label: Text("小队本周目标 · 人均 \(squad.daysPerMember) 天", bundle: .module), title: squad.name,
                count: squad.done, goal: squad.goal, unit: Text("天", bundle: .module), open: openSquad)
            Spacer(minLength: gap)
            DayCells(filled: squad.done, total: squad.goal)
            Spacer(minLength: gap)
            ViewThatFits(in: .horizontal) {
                todayRings(avatarSize: Sizing.characterHead, spacing: SquadCardMetrics.ringSpacing)
                todayRings(avatarSize: SquadCardMetrics.compactAvatar, spacing: SquadCardMetrics.compactRingSpacing)
                todayRings(avatarSize: SquadCardMetrics.narrowAvatar, spacing: SquadCardMetrics.compactRingSpacing)
            }
            if let footer {
                Spacer(minLength: gap)
                footer
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Everyone's ring, which shows their today, after a 今天 label.
    private func todayRings(avatarSize: Double, spacing: Double) -> some View {
        HStack(spacing: Space.xs) {
            SectionLabel(Text("今天", bundle: .module))
                .fixedSize()
            rings(avatarSize: avatarSize, spacing: spacing)
        }
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

#endif
