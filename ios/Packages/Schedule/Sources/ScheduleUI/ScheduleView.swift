#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import ScheduleDomain
import SportsUI
import SwiftUI

/// 出赛表: the week as a poster the member plans on. Chips pick the week (back to the one they
/// joined, this week, next week); 存图 saves the poster to Photos; under the poster sit the
/// picks for the day in hand, next week's 饮食小目标, or the counts. The tab bar is the app's:
/// this screen keeps to the safe area the app gives it and draws no bar.
public struct ScheduleView: View {
    let model: ScheduleModel
    @Environment(\.sceneTheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var picksAll = false
    @State private var ownFuel = ""
    @FocusState private var typingFuel: Bool

    private static let panelID = "schedule.panel"
    /// How long 存好了 stays before it goes.
    private let savedNoteHold: Duration = .seconds(2.4)

    public init(model: ScheduleModel) {
        self.model = model
    }

    private var store: ScheduleStore { model.store }

    public var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    topBar
                    if let sheet = store.sheet {
                        poster(sheet)
                        panel(sheet)
                            .id(Self.panelID)
                    } else {
                        loading
                    }
                }
                .padding(.horizontal, Space.pageMargin)
                .padding(.top, Space.xs)
                .padding(.bottom, Space.l)
                .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: model.panel)
            }
            // On a shorter phone the picks can open below the fold: bring them up over the bar.
            .onChange(of: model.panel) { _, panel in
                guard panel != .counts else { return }
                withAnimation(.wildcard(Motion.page, reduceMotion: reduceMotion)) {
                    scroller.scrollTo(Self.panelID, anchor: .bottom)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(role: .bgCanvas, in: theme).ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            if model.writingFuel {
                fuelField
            }
        }
        .task { await model.load() }
        .sheet(isPresented: $picksAll) {
            SportPicker(selected: selectedActivity) { activity in
                picksAll = false
                model.pick(activity)
            }
        }
        .haptic(.pick, trigger: model.taps)
        .haptic(.land, trigger: model.swaps)
        .haptic(.appear, trigger: model.saving == .saved)
        .task(id: model.saving) {
            guard model.saving == .saved || model.saving == .failed else { return }
            try? await Task.sleep(for: savedNoteHold)
            model.clearSaving()
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: Space.xs) {
            CategoryBar(weekChips, selection: weekSelection)
                .defaultScrollAnchor(.trailing)
                .frame(maxWidth: .infinity)
            Button {
                Task { await save() }
            } label: {
                Label {
                    Text("存图", bundle: .module)
                } icon: {
                    Image(systemName: model.saving == .saved ? "checkmark" : "square.and.arrow.down")
                        .font(.system(size: Sizing.smallIcon + 2, weight: .medium))
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(store.sheet == nil || model.saving == .working)
            .accessibilityIdentifier("schedule.save")
        }
    }

    private var weekChips: [CategoryBarItem<LocalDay>] {
        let thisWeek = store.today?.weekStart
        return store.weeks.map { week in
            let title: Text =
                if week == thisWeek {
                    Text("本周", bundle: .module)
                } else if let thisWeek, week > thisWeek {
                    Text("下周", bundle: .module)
                } else {
                    Text(verbatim: ScheduleLabels.week(week))
                }
            return CategoryBarItem(id: week, title: title, accessibilityIdentifier: "schedule.week.\(week)")
        }
    }

    private var weekSelection: Binding<LocalDay> {
        Binding(
            get: { store.shownWeek ?? store.today?.weekStart ?? LocalDay(at: .now, in: .current) },
            set: { model.show($0) })
    }

    @ViewBuilder
    private var loading: some View {
        switch store.phase {
        case .offline:
            Text("网不太好，连上了再来排", bundle: .module)
                .typeStyle(TypeRamp.body)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
        case .signedOut:
            Text("登录过期了，重新登录再来排", bundle: .module)
                .typeStyle(TypeRamp.body)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
        case .loading, .ready:
            Color(role: .bgSubtle, in: theme)
                .aspectRatio(WeekPoster.size.width / WeekPoster.size.height, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }

    // MARK: Poster

    private func content(_ sheet: WeekSheet) -> PosterContent {
        PosterContent(
            sheet: sheet, board: store.board, nickname: store.profile?.nickname ?? "", openTitle: model.openTitle,
            fuelOpen: model.panel == .fuel)
    }

    private func poster(_ sheet: WeekSheet) -> some View {
        GeometryReader { proxy in
            WeekPoster(
                content: content(sheet), player: model.player, onTapLane: model.tap, onTapTitle: model.toggle,
                onTapFuel: model.toggleFuelPanel
            )
            .scaleEffect(proxy.size.width / WeekPoster.size.width, anchor: .topLeading)
        }
        .aspectRatio(WeekPoster.size.width / WeekPoster.size.height, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule.poster")
    }

    @MainActor private func save() async {
        guard let sheet = store.sheet else { return }
        let still = WeekPoster(content: content(sheet).forSaving, player: model.player, isStill: true)
        await model.savePoster { WeekPoster.picture(of: still, theme: theme, locale: locale) }
    }

    // MARK: Under the poster

    @ViewBuilder
    private func panel(_ sheet: WeekSheet) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            switch model.panel {
            case .counts:
                if store.board?.tense == .upcoming {
                    CountdownCard(store: store)
                } else {
                    counts(sheet)
                }
            case .dayPicks(let index):
                dayPicks(sheet, index)
            case .fuel:
                fuelPicks(sheet)
            }
            note
        }
        .transition(.opacity)
    }

    private func counts(_ sheet: WeekSheet) -> some View {
        let isPast = store.board?.tense == .past
        return HStack(alignment: .top, spacing: Space.cardGap) {
            if isPast {
                CountCard(
                    label: Text("这周练了", bundle: .module), count: sheet.trainedDays, goal: sheet.plannedDays,
                    unit: Text("天", bundle: .module)
                )
                .accessibilityIdentifier("schedule.count.week")
            } else {
                CountCard(
                    label: Text("一共练了", bundle: .module), count: store.lifetimeTrainedDays ?? 0, goal: nil,
                    unit: Text("天", bundle: .module)
                )
                .accessibilityIdentifier("schedule.count.lifetime")
            }
            if let squad = sheet.squad {
                CountCard(
                    label: isPast ? Text("小队训练", bundle: .module) : Text("本周小队训练", bundle: .module),
                    count: squad.trained, goal: squad.planned, unit: Text("次", bundle: .module)
                )
                .accessibilityIdentifier("schedule.count.squad")
            }
        }
    }

    private func dayPicks(_ sheet: WeekSheet, _ index: Int) -> some View {
        let day = sheet.weekStart.adding(days: index)
        let plan = sheet.plan[index]
        return VStack(alignment: .leading, spacing: Space.labelGap) {
            SectionLabel(
                Text("\(ScheduleLabels.weekday(day)) · \(ScheduleLabels.shortDate(day))", bundle: .module))
            FlowRow {
                ForEach(store.suggestedActivities, id: \.key) { activity in
                    PickPill(activity.name, systemImage: activity.symbol, isSelected: plan == .train(activity)) {
                        model.pick(activity)
                    }
                    .accessibilityIdentifier("schedule.pick.\(activity.key)")
                }
                if store.board?.offersRest == true {
                    PickPill(Text("休息", bundle: .module), systemImage: "moon", isSelected: plan == .rest) {
                        model.rest()
                    }
                    .accessibilityIdentifier("schedule.pick.rest")
                }
                PickPill(Text("更多", bundle: .module), systemImage: "magnifyingglass", isSelected: false) {
                    picksAll = true
                }
                .accessibilityIdentifier("schedule.pick.more")
            }
        }
    }

    private var selectedActivity: Activity {
        guard let sheet = store.sheet, case .selected(let index) = store.board?.focus,
            case .train(let activity?) = sheet.plan[index]
        else { return .sport(.run) }
        return activity
    }

    private func fuelPicks(_ sheet: WeekSheet) -> some View {
        let full = sheet.fuel.count >= FuelGoal.maxCount
        let own = sheet.fuel.filter { if case .own = $0 { true } else { false } }
        let goals = FuelSuggestion.allCases.map(FuelGoal.suggested) + own
        return VStack(alignment: .leading, spacing: Space.labelGap) {
            SectionLabel(Text("饮食小目标 · \(sheet.fuel.count)/\(FuelGoal.maxCount)", bundle: .module))
            FlowRow {
                ForEach(goals, id: \.self) { goal in
                    PickPill(ScheduleLabels.fuel(goal), isSelected: sheet.fuel.contains(goal)) {
                        model.toggle(goal)
                    }
                    .accessibilityIdentifier("schedule.fuel.\(ScheduleLabels.fuelName(goal))")
                }
                PickPill(Text("自己写", bundle: .module), systemImage: "plus", isSelected: false) {
                    ownFuel = ""
                    model.writingFuel = true
                    typingFuel = true
                }
                .disabled(full)
                .opacity(full ? 0.4 : 1)
                .accessibilityIdentifier("schedule.fuel.own")
            }
        }
    }

    /// What became of the last save or 存图, for a moment.
    @ViewBuilder
    private var note: some View {
        if model.saving == .saved {
            Text("存好了，去相册看看", bundle: .module)
                .noteStyle(theme)
                .accessibilityIdentifier("schedule.saved")
        } else if model.saving == .notAllowed {
            HStack(spacing: Space.xs) {
                Text("要先允许存到相册", bundle: .module)
                    .noteStyle(theme)
                if let settings = URL(string: UIApplication.openSettingsURLString) {
                    Link(destination: settings) {
                        Text("去设置", bundle: .module)
                    }
                    .buttonStyle(TextButtonStyle(.plain))
                }
            }
        } else if model.saving == .failed {
            Text("没存上，再试一次", bundle: .module)
                .noteStyle(theme)
        } else if let failure = store.failure {
            ScheduleLabels.failure(failure)
                .noteStyle(theme)
                .accessibilityIdentifier("schedule.failure")
        }
    }

    // MARK: Own 饮食小目标

    private var fuelField: some View {
        HStack(spacing: Space.xs) {
            InputField(
                text: $ownFuel, label: Text("饮食小目标", bundle: .module),
                limit: FuelGoal.maxLength
            )
            .focused($typingFuel)
            .submitLabel(.done)
            .onSubmit { Task { await addOwnFuel() } }
            .accessibilityIdentifier("schedule.fuel.field")
            Button {
                Task { await addOwnFuel() }
            } label: {
                Text("加上", bundle: .module)
            }
            .buttonStyle(PrimaryButtonStyle(.regular))
            .disabled(ownFuel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("schedule.fuel.add")
        }
        .padding(.horizontal, Space.pageMargin)
        .padding(.vertical, Space.xs)
        .background(Color(role: .bgCanvas, in: theme))
        .onChange(of: typingFuel) { _, focused in
            if !focused { model.writingFuel = false }
        }
    }

    private func addOwnFuel() async {
        if await model.addFuel(typed: ownFuel) {
            ownFuel = ""
            typingFuel = false
        }
    }
}

/// A label over a number and its unit, on a grey card: 一共练了 46 天, 本周小队训练 14/22 次.
private struct CountCard: View {
    let label: Text
    let count: Int
    let goal: Int?
    let unit: Text
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.labelGap) {
            SectionLabel(label)
            HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
                Score(count: count, goal: goal, size: .card)
                unit
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(on: .page)
        .accessibilityElement(children: .combine)
    }
}

/// Next week: how long until it starts, ticking every second, and the Monday it starts on.
private struct CountdownCard: View {
    let store: ScheduleStore
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: Space.labelGap) {
                    SectionLabel(Text("离开赛还有", bundle: .module))
                    if let left = store.untilNextWeek {
                        HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
                            Score(count: left.days, size: .card)
                            Text("天", bundle: .module)
                                .typeStyle(TypeRamp.footnote)
                                .foregroundStyle(Color(role: .fgMuted, in: theme))
                            Text(
                                verbatim: String(format: "%02d:%02d:%02d", left.hours, left.minutes, left.seconds)
                            )
                            .typeStyle(TypeRamp.scoreCard)
                            .monospacedDigit()
                            .foregroundStyle(Color(role: .fgDefault, in: theme))
                            .padding(.leading, Space.xs - 2)
                        }
                    }
                }
                Spacer(minLength: Space.xs)
                if let start = store.shownWeek {
                    Text("周一 \(ScheduleLabels.shortDate(start))", bundle: .module)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(on: .page)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("schedule.countdown")
    }
}

extension View {
    /// A short note under the poster: what just happened.
    fileprivate func noteStyle(_ theme: SceneTheme) -> some View {
        typeStyle(TypeRamp.footnote)
            .foregroundStyle(Color(role: .fgMuted, in: theme))
    }
}
#endif
