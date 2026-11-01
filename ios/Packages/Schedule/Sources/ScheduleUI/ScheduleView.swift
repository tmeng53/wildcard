#if os(iOS)
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import ScheduleDomain
import SportsUI
import SwiftUI

/// 出赛表: the week as a poster the member plans on. Chips pick the week (back to the one they
/// joined, this week, next week) or the 每周模板, on a graphite poster of its own; 存图 saves a
/// week's poster to Photos; under the poster sit the picks for the day in hand, next week's
/// 饮食小目标, or the counts. The tab bar is the app's:
/// this screen keeps to the safe area the app gives it and draws no bar.
public struct ScheduleView: View {
    let model: ScheduleModel
    @Environment(\.sceneTheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var picksAll = false
    @State private var ownFuel = ""
    @FocusState private var typingFuel: Bool
    /// Bumps as 存图 takes its picture: the poster flashes white, like a screenshot.
    @State private var flashes = 0
    /// The picture the share sheet is open on, once the flash has played.
    @State private var sharing: ScheduleModel.SharedPoster?

    private static let panelID = "schedule.panel"
    private static let posterID = "schedule.posterFrame"
    /// How long 没存上 stays before it goes.
    private let failedNoteHold: Duration = .seconds(5)

    public init(model: ScheduleModel) {
        self.model = model
    }

    private var store: ScheduleStore { model.store }

    public var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    if let shown = shownContent {
                        poster(shown)
                            .id(Self.posterID)
                        panel(store.sheet)
                            .id(Self.panelID)
                    } else {
                        loading
                    }
                }
                // Over the poster and the placeholder alike, so the character stays its minimum
                // and fades out over the poster that arrived.
                .loadingCover(store.phase == .loading) { PosterLoader() }
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
        .onChange(of: theme, initial: true) { _, scene in model.train(on: scene) }
        .sheet(isPresented: $picksAll) {
            SportPicker(selected: selectedActivity, recent: recentActivities) { activity in
                picksAll = false
                model.pick(activity)
            }
        }
        .haptic(.appear, trigger: sharing?.id)
        .task(id: model.saving) {
            switch model.saving {
            case .sharing(let poster):
                // The poster flashes, then the share sheet opens on its picture.
                flashes += 1
                // Left mid-flash (another tab), the share sheet doesn't open later on its own.
                guard (try? await Task.sleep(for: .seconds(Motion.fadeIn.duration))) != nil else {
                    model.clearSaving()
                    return
                }
                sharing = poster
            case .failed:
                try? await Task.sleep(for: failedNoteHold)
                model.clearSaving()
            case .idle, .working:
                break
            }
        }
        .sheet(
            item: $sharing, onDismiss: { model.clearSaving() },
            content: { poster in
                PosterShareSheet(image: poster.image)
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            })
    }

    // MARK: Poster

    private func content(_ sheet: WeekSheet) -> PosterContent {
        PosterContent(
            sheet: sheet, board: store.board, nickname: store.profile?.nickname ?? "",
            weekNumber: store.profile?.weekNumber(of: sheet.weekStart) ?? 1, fuelOpen: model.panel == .fuel,
            typingFuel: model.writingFuel ? ownFuel : "")
    }

    /// The week shown, or the 每周模板.
    private var shownContent: PosterContent? {
        if store.showsTemplate {
            return store.board.map { PosterContent(template: $0, nickname: store.profile?.nickname ?? "") }
        }
        return store.sheet.map(content)
    }

    private func poster(_ content: PosterContent) -> some View {
        GeometryReader { proxy in
            SchedulePoster(
                content: content, player: model.player, onTapLane: model.tap,
                onTapFuel: model.toggleFuelPanel
            )
            .scaleEffect(proxy.size.width / SchedulePoster.size.width, anchor: .topLeading)
        }
        .keyframeAnimator(initialValue: 0.0, trigger: flashes) { content, flash in
            content.overlay { Color(role: .bgCanvas, in: theme).opacity(flash).allowsHitTesting(false) }
        } keyframes: { _ in
            LinearKeyframe(1, duration: 0.01)
            CubicKeyframe(0, duration: Motion.fadeIn.duration)
        }
        .aspectRatio(SchedulePoster.size.width / SchedulePoster.size.height, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule.poster")
    }

    @MainActor private func save() {
        guard let sheet = store.sheet else { return }
        let still = SchedulePoster(content: content(sheet).forSaving, player: model.player, still: model.keyPose)
        model.sharePoster { SchedulePoster.picture(of: still, theme: theme, locale: locale) }
    }

    // MARK: Under the poster

    /// `sheet` is the week shown; nil on the 每周模板.
    @ViewBuilder
    private func panel(_ sheet: WeekSheet?) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            switch model.panel {
            case .counts:
                counts(sheet)
            case .dayPicks(let index):
                if let board = store.board {
                    DayPicks(store: store, board: board, index: index, onPick: model.pick, onRest: model.rest) {
                        picksAll = true
                    }
                }
            case .fuel:
                if let sheet { fuelPicks(sheet) }
            }
            PanelNote(store: store)
            if store.showsTemplate {
                TemplateNote()
            } else if store.templateOffer != nil {
                TemplateOffer(onCopy: model.copyToTemplate)
                    .transition(.opacity)
            }
        }
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: store.templateOffer)
        // The offer goes by itself after a few seconds; another change brings it back.
        .task(id: store.templateOffer) {
            guard store.templateOffer != nil, (try? await Task.sleep(for: model.templateOfferHold)) != nil else {
                return
            }
            store.dismissTemplateOffer()
        }
        .transition(.opacity)
    }

    /// Under a week with nothing in hand: next week's countdown, this week's counts or a past
    /// week's awards; nothing under the 每周模板, whose note says when it counts.
    @ViewBuilder
    private func counts(_ sheet: WeekSheet?) -> some View {
        switch (store.board?.tense, sheet) {
        case (.upcoming, _): CountdownCard(store: store)
        case (.current, let sheet?): ScheduleCounts(store: store, sheet: sheet)
        case (.past, let sheet?), (nil, let sheet?): WeekAwards(titles: sheet.titles)
        default: EmptyView()
        }
    }

    /// 常用运动: the sports in the week on the poster, in the order planned.
    private var recentActivities: [Activity] {
        var seen: [Activity] = []
        for case .train(let activity?) in store.board?.days ?? [] where !seen.contains(activity) {
            seen.append(activity)
        }
        return seen
    }

    private var selectedActivity: Activity {
        guard let board = store.board, case .selected(let index) = board.focus,
            case .train(let activity?) = board.days[index]
        else { return .sport("run") }
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
        } else {
            // The tap on 加上 put the keyboard away; bring the typed goal back to try again.
            model.writingFuel = true
            typingFuel = true
        }
    }
}

extension ScheduleView {
    // MARK: Top bar

    fileprivate var topBar: some View {
        HStack(spacing: Space.xs) {
            CategoryBar(pageChips, selection: pageSelection)
                .frame(maxWidth: .infinity)
            // The 每周模板 is no one week's poster to share.
            if !store.showsTemplate {
                saveButton
            }
        }
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Label {
                Text("存图", bundle: .module)
            } icon: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: Sizing.smallIcon + 2, weight: .medium))
            }
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(store.sheet == nil || model.saving != .idle && model.saving != .failed)
        .accessibilityIdentifier("schedule.save")
    }

    /// The weeks, then the 每周模板 after a hairline.
    fileprivate var pageChips: [CategoryBarItem<SchedulePage>] {
        guard !store.weeks.isEmpty else { return [] }
        return weekChips + [
            CategoryBarItem(
                id: .template, title: Text("每周模板", bundle: .module), systemImage: WeekPosterHeading.templateSymbol,
                startsGroup: true, accessibilityIdentifier: "schedule.template")
        ]
    }

    fileprivate var weekChips: [CategoryBarItem<SchedulePage>] {
        let thisWeek = store.today?.weekStart
        return store.weeks.map { week in
            let title: Text =
                if week == thisWeek {
                    Text("本周", bundle: .module)
                } else if let thisWeek, week > thisWeek {
                    Text("下周", bundle: .module)
                } else {
                    Text(verbatim: ScheduleLabels.week(store.profile?.weekNumber(of: week) ?? 1))
                }
            return CategoryBarItem(id: .week(week), title: title, accessibilityIdentifier: "schedule.week.\(week)")
        }
    }

    private var pageSelection: Binding<SchedulePage> {
        Binding(
            get: {
                store.showsTemplate
                    ? .template : .week(store.shownWeek ?? store.today?.weekStart ?? LocalDay(at: .now, in: .current))
            },
            set: { page in
                switch page {
                case .week(let week): model.show(week)
                case .template: model.showTemplate()
                }
            })
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
            // The poster's place until the weeks are read; the character jogs over it.
            Color(role: .bgSubtle, in: theme)
                .aspectRatio(SchedulePoster.size.width / SchedulePoster.size.height, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }
}

#endif
