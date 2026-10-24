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
    private static let posterID = "schedule.posterFrame"
    /// How long 存好了 stays before it goes: long enough to read after looking up from the tap,
    /// and for a UI test to find it after a slow render.
    private let savedNoteHold: Duration = .seconds(5)

    public init(model: ScheduleModel) {
        self.model = model
    }

    private var store: ScheduleStore { model.store }

    public var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    if let sheet = store.sheet {
                        poster(sheet)
                            .id(Self.posterID)
                        panel(sheet)
                            .id(Self.panelID)
                    } else {
                        loading
                    }
                }
                .padding(.horizontal, Space.pageMargin)
                .padding(.top, Space.s)
                .padding(.bottom, Space.l)
                .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: model.panel)
            }
            // Typing a goal of their own: the poster's bottom, where it shows as it is typed, sits
            // just over the field.
            .onChange(of: model.writingFuel) { _, writing in
                guard writing else { return }
                withAnimation(.wildcard(Motion.page, reduceMotion: reduceMotion)) {
                    scroller.scrollTo(Self.posterID, anchor: .bottom)
                }
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
        // The weeks and 存图 stay put while the poster scrolls, so nothing slides under the
        // status bar.
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.xs) {
                topBar
                SaveNote(saving: model.saving)
            }
            .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: model.saving)
            .padding(.horizontal, Space.pageMargin)
            .padding(.top, Space.xs)
            .background(Color(role: .bgCanvas, in: theme))
        }
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
            sheet: sheet, board: store.board, nickname: store.profile?.nickname ?? "", fuelOpen: model.panel == .fuel,
            typingFuel: model.writingFuel ? ownFuel : "")
    }

    private func poster(_ sheet: WeekSheet) -> some View {
        GeometryReader { proxy in
            WeekPoster(
                content: content(sheet), player: model.player, onTapLane: model.tap,
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
                switch store.board?.tense {
                case .upcoming: CountdownCard(store: store)
                case .current: ScheduleCounts(store: store, sheet: sheet)
                case .past, nil: WeekAwards(titles: sheet.titles)
                }
            case .dayPicks(let index):
                DayPicks(store: store, sheet: sheet, index: index, onPick: model.pick, onRest: model.rest) {
                    picksAll = true
                }
            case .fuel:
                fuelPicks(sheet)
            }
            PanelNote(store: store)
        }
        .transition(.opacity)
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
#endif
