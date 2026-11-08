#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import SportsUI
import SwiftUI

/// One page like a social app's new post (spec rev 186, section 1; on the 入场券 since
/// 2026-11-08): 取消 / title / 发布, then the ticket: the line above its tear (up to 60
/// characters, its count always showing), the photos below it as 3:4 tiles with their cover and
/// 「+ 照片」 (a meal's three across the stub, big); under the ticket the sport and minutes for a
/// 训练. Minutes are optional; no meal type. A new 训练 offers today's Apple Health workouts
/// (检测到的运动): one picked sets the sport, puts its numbers in the minutes' place, a cell each,
/// and its map or chart among the tiles. Editing a saved post opens the same page with 保存, and
/// its squads stay as posted. Leaving with something added or changed asks first.
public struct ComposeView: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: ComposeModel
    @FocusState private var isWriting: Bool
    @State private var isPickingSport = false
    @State private var isRulingMinutes = false
    @State private var isDiscarding = false

    public init(model: ComposeModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            bar
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.l) {
                        TicketCard {
                            captionField
                        } stub: {
                            PhotoTiles(model: model)
                        }
                        if model.kind == .trained, !model.isEditing, !model.healthWorkouts.isEmpty {
                            HealthChips(model: model)
                        }
                        if let today = model.postableDays.last, model.postableDays.count > 1 {
                            VStack(alignment: .leading, spacing: Space.xxs) {
                                SectionLabel(Text("日期", bundle: .module))
                                DayPick(
                                    days: model.postableDays,
                                    picked: Binding {
                                        model.day ?? today
                                    } set: {
                                        model.day = $0 == today ? nil : $0
                                    })
                            }
                        }
                        if model.kind == .trained {
                            SportRow(
                                selected: model.currentActivity, isPickingSport: $isPickingSport
                            ) { model.activity = $0 }
                            if model.workout != nil {
                                ScoreRow(model: model)
                            } else {
                                MinutesRow(minutes: $model.minutes, isRuling: $isRulingMinutes)
                                    .id(Self.minutesID)
                            }
                        }
                        if model.sendFailed {
                            failedLine
                                .typeStyle(TypeRamp.footnote)
                                .foregroundStyle(Color(role: .fgMuted, in: theme))
                                .accessibilityIdentifier("compose.failed")
                        }
                    }
                    .padding(.horizontal, Space.pageMargin)
                    .padding(.vertical, Space.m)
                }
                .scrollDismissesKeyboard(.interactively)
                // Keep the ruler 其他 opens in view.
                .onChange(of: isRulingMinutes) { _, ruling in
                    guard ruling else { return }
                    withAnimation(.wildcard(Motion.page, reduceMotion: reduceMotion)) {
                        proxy.scrollTo(Self.minutesID, anchor: .bottom)
                    }
                }
            }
        }
        .actionBar(isShown: !model.isEditing && model.shareSquad != nil) {
            if let squad = model.shareSquad {
                ShareRow(squad: squad, isShared: $model.isShared)
            }
        }
        .background(Color(role: .bgCanvas, in: theme).ignoresSafeArea())
        .sheet(isPresented: $isPickingSport) {
            SportPicker(selected: model.currentActivity, recent: model.recentActivities) { picked in
                model.activity = picked
                isPickingSport = false
            }
            .environment(\.sceneTheme, theme)
            .accentTone(.brand)
        }
        // An alert, not a confirmation dialog: iOS 26 drops a dialog's cancel button, and the
        // design shows 继续编辑 beside 放弃.
        .alert(
            model.isEditing ? Text("放弃这些修改？", bundle: .module) : Text("放弃这条动态？", bundle: .module),
            isPresented: $isDiscarding
        ) {
            Button(role: .destructive) {
                model.close()
            } label: {
                Text("放弃", bundle: .module)
            }
            .accessibilityIdentifier("compose.discard")
            Button(role: .cancel) {
            } label: {
                Text("继续编辑", bundle: .module)
            }
            .accessibilityIdentifier("compose.keepEditing")
        }
    }

    private static let minutesID = "minutes"

    private var failedLine: Text {
        model.isEditing ? Text("没保存上，再点一次保存", bundle: .module) : Text("没发出去，再点一次发布", bundle: .module)
    }

    private var bar: some View {
        ComposeBar(
            title: model.kind.fullName,
            finish: model.isEditing ? Text("保存", bundle: .module) : Text("发布", bundle: .module),
            isWorking: model.isSending, canFinish: !model.isSending && model.canSave,
            cancelID: "compose.cancel", finishID: "compose.post",
            cancel: { if model.hasChanges { isDiscarding = true } else { model.close() } },
            done: { Task { await model.send() } })
    }

    /// The line, on the ticket's face: room for its four lines from the start, so the ticket
    /// doesn't jump while typing, and its count under it. A line has no breaks: return closes
    /// the keyboard, as 完成 did.
    private var captionField: some View {
        VStack(alignment: .trailing, spacing: Space.xxs) {
            TextField(text: $model.line, axis: .vertical) { placeholder }
                .typeStyle(TypeRamp.field)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .lineLimit(Self.lines, reservesSpace: true)
                .focused($isWriting)
                .submitLabel(.done)
                .onChange(of: model.line) { _, typed in
                    if typed.contains(where: \.isNewline) { isWriting = false }
                    let fitted = model.fit(typed)
                    if fitted != typed { model.line = fitted }
                }
                .accessibilityIdentifier("compose.caption")
            Text(verbatim: "\(model.line.count)/\(model.lineLimit)")
                .typeStyle(TypeRamp.caption)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .monospacedDigit()
                .accessibilityIdentifier("compose.count")
        }
    }

    /// Lines the field keeps room for: 60 characters fit in three on the smallest phone.
    private static let lines = 4

    private var placeholder: Text {
        switch model.kind {
        case .trained: Text("炫耀一下成果…", bundle: .module)
        case .healthyMeal: Text("这顿很自律…", bundle: .module)
        case .cheatMeal: Text("坦白从宽…", bundle: .module)
        case .disclaimer: Text("今天为什么请假…", bundle: .module)
        }
    }
}

/// The sport: the current one first, a few common ones, and 更多 for the full list.
private struct SportRow: View {
    let selected: Activity
    @Binding var isPickingSport: Bool
    let pick: (Activity) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            SectionLabel(Text("运动", bundle: .module))
            ScrollView(.horizontal) {
                HStack(spacing: Space.xs) {
                    ForEach(choices, id: \.key) { activity in
                        PickPill(
                            activity.name, systemImage: activity.symbol, look: .solid, isSelected: activity == selected
                        ) {
                            pick(activity)
                        }
                        .accessibilityIdentifier("compose.sport.\(activity.key)")
                    }
                    PickPill(Text("更多", bundle: .module), systemImage: "ellipsis", isSelected: false) {
                        isPickingSport = true
                    }
                    .accessibilityIdentifier("compose.sport.more")
                }
            }
            .scrollIndicators(.hidden)
            .horizontalScrollFade()
        }
    }

    private var choices: [Activity] {
        [selected] + SportList.shared.catalog.checkInQuick.map(Activity.sport).filter { $0 != selected }
    }
}

/// How long it took, if the member wants to say: the usual lengths one tap each (tap again to
/// clear), and 其他 for any other length on a ruler, which starts on the length last picked.
private struct MinutesRow: View {
    @Binding var minutes: WorkoutMinutes?
    @Binding var isRuling: Bool
    @State private var ruled = Self.rulerStart

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            SectionLabel(Text("时长 · 分钟", bundle: .module))
            ScrollView(.horizontal) {
                HStack(spacing: Space.xs) {
                    ForEach(Self.quickPicks, id: \.self) { value in
                        let isPicked = !isRuling && minutes?.value == value
                        PickPill(Text(verbatim: "\(value)"), look: .solid, isSelected: isPicked) {
                            isRuling = false
                            minutes = isPicked ? nil : try? WorkoutMinutes(value)
                        }
                        .accessibilityLabel(Text("\(value) 分钟", bundle: .module))
                        .accessibilityIdentifier("compose.minutes.\(value)")
                    }
                    PickPill(Text("其他", bundle: .module), look: .solid, isSelected: isRuling) {
                        if isRuling {
                            isRuling = false
                            minutes = nil
                        } else {
                            ruled = Self.scale.snapped(minutes?.value ?? Self.rulerStart)
                            minutes = try? WorkoutMinutes(ruled)
                            isRuling = true
                        }
                    }
                    .accessibilityIdentifier("compose.minutes.other")
                }
            }
            .scrollIndicators(.hidden)
            .horizontalScrollFade()
            if isRuling {
                TickRuler(
                    value: $ruled, scale: Self.scale, label: Text("时长 · 分钟", bundle: .module),
                    unit: Text("分钟", bundle: .module)
                )
                .padding(.top, Space.xs)
                .onChange(of: ruled) { _, value in minutes = try? WorkoutMinutes(value) }
                .accessibilityIdentifier("compose.minutes.ruler")
            }
        }
    }

    /// Any minute from 1 to 6 hours; the API takes up to 600, but a ruler that long is hard to slide.
    private static let scale = RulerScale(range: 1...360, step: 1, midEvery: 5, labelEvery: 15)
    /// Where the ruler starts when no usual length was picked first.
    private static let rulerStart = 60
    private static let quickPicks = [30, 60, 90]
}
#endif
