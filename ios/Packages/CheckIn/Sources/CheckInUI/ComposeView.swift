#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import SportsUI
import SwiftUI

/// One page like a social app's new post (spec rev 186, section 1): 取消 / title / 发布, the
/// photos with their cover, the sport and minutes for a 练了, and a line up to 60 characters.
/// Minutes are optional; no meal type.
struct ComposeView: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: TodayModel
    let kind: CheckInKind
    @State private var caption = ""
    @FocusState private var isWriting: Bool
    @State private var activity: Activity?
    @State private var isPickingSport = false
    @State private var minutes: WorkoutMinutes?
    @State private var isRulingMinutes = false
    /// Where the caption starts on the page, so it can fill the page below.
    @State private var captionTop = 0.0

    var body: some View {
        VStack(spacing: 0) {
            bar
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.l) {
                        MediaBlock(model: model)
                        if kind == .trained {
                            SportRow(selected: currentActivity, isPickingSport: $isPickingSport) { activity = $0 }
                            MinutesRow(minutes: $minutes, isRuling: $isRulingMinutes)
                                .id(Self.minutesID)
                        }
                        captionField.id(Self.captionID)
                        if model.sendFailed {
                            Text("没发出去，再点一次发布", bundle: .module)
                                .typeStyle(TypeRamp.footnote)
                                .foregroundStyle(Color(role: .fgMuted, in: theme))
                                .accessibilityIdentifier("compose.failed")
                        }
                    }
                    .padding(.horizontal, Space.pageMargin)
                    .padding(.vertical, Space.m)
                    .coordinateSpace(.named(Self.pageSpace))
                }
                .scrollDismissesKeyboard(.interactively)
                // Keep the line being written above the keyboard.
                .onChange(of: isWriting) { _, writing in
                    guard writing else { return }
                    withAnimation(.wildcard(Motion.page, reduceMotion: reduceMotion)) {
                        proxy.scrollTo(Self.captionID, anchor: .bottom)
                    }
                }
                // And the ruler 其他 opens.
                .onChange(of: isRulingMinutes) { _, ruling in
                    guard ruling else { return }
                    withAnimation(.wildcard(Motion.page, reduceMotion: reduceMotion)) {
                        proxy.scrollTo(Self.minutesID, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(role: .bgCanvas, in: theme).ignoresSafeArea())
        .sheet(isPresented: $isPickingSport) {
            SportPicker(selected: currentActivity, recent: model.recentActivities) { picked in
                activity = picked
                isPickingSport = false
            }
            .environment(\.sceneTheme, theme)
            .accentTone(.brand)
        }
    }

    private static let captionID = "caption"
    private static let minutesID = "minutes"
    private static let pageSpace = "compose.page"

    /// The board's last sport until the member picks one; detection from the cover comes later.
    private var currentActivity: Activity {
        activity ?? model.suggestedActivity
    }

    private var bar: some View {
        HStack {
            Button {
                model.cancel()
            } label: {
                Text("取消", bundle: .module)
                    .typeStyle(TypeRamp.body)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .frame(minHeight: Sizing.minimumTapTarget)
            }
            .accessibilityIdentifier("compose.cancel")
            Spacer()
            Button {
                Task { await model.post(draft) }
            } label: {
                Text("发布", bundle: .module)
                    .typeStyle(TypeRamp.headline)
                    .loadingLabel(model.isSending)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
            }
            .frame(minHeight: Sizing.minimumTapTarget)
            .disabled(model.isSending)
            .accessibilityIdentifier("compose.post")
        }
        .overlay {
            kind.fullName
                .typeStyle(TypeRamp.headline)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, Space.pageMargin)
        .padding(.vertical, Space.xxs)
    }

    /// The caption fills the page below what's above it, so a tap anywhere on the white starts
    /// typing. A line has no breaks: return closes the keyboard, as 完成 did.
    private var captionField: some View {
        VStack(alignment: .trailing, spacing: Space.xxs) {
            TextEditor(text: $caption)
                .typeStyle(TypeRamp.field)
                .scrollContentBackground(.hidden)
                .focused($isWriting)
                .overlay(alignment: .topLeading) {
                    if caption.isEmpty {
                        placeholder
                            .typeStyle(TypeRamp.field)
                            .foregroundStyle(Color(role: .fgSubtle, in: theme))
                            .padding(.top, Self.editorInset.top)
                            .padding(.leading, Self.editorInset.leading)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .containerRelativeFrame(.vertical) { page, _ in
                    max(page - captionTop - Space.m - Self.countRoom, Sizing.minimumTapTarget)
                }
                .onGeometryChange(for: Double.self) {
                    $0.frame(in: .named(Self.pageSpace)).minY
                } action: {
                    captionTop = $0
                }
                .padding(.horizontal, -Self.editorInset.leading)
                .onChange(of: caption) { _, typed in
                    if typed.contains(where: \.isNewline) { isWriting = false }
                    let fitted = PostBody.fitCaption(typed)
                    if fitted != typed { caption = fitted }
                }
                .accessibilityLabel(placeholder)
                .accessibilityIdentifier("compose.caption")
            // The count shows only near the limit, so the field stays quiet.
            if caption.count >= Caption.maxLength - 10 {
                Text(verbatim: "\(caption.count)/\(Caption.maxLength)")
                    .typeStyle(TypeRamp.label)
                    .foregroundStyle(Color(role: .fgSubtle, in: theme))
                    .monospacedDigit()
            }
        }
    }

    /// Where `TextEditor` (a text view) starts its first line inside its frame, which the
    /// placeholder matches; its leading inset hangs into the page margin so the text lines up
    /// with the rows above.
    private static let editorInset = (top: 8.0, leading: 5.0)
    /// Room kept under the caption for its count near the limit.
    private static let countRoom = 20.0

    private var placeholder: Text {
        switch kind {
        case .trained: Text("炫耀一下成果…", bundle: .module)
        case .healthyMeal: Text("这顿很自律…", bundle: .module)
        case .cheatMeal, .disclaimer: Text("坦白从宽…", bundle: .module)
        }
    }

    private var draft: CheckInDraft {
        let body = PostBody(photos: model.photos, caption: caption)
        return switch kind {
        case .trained: .trained(currentActivity, minutes, body)
        case .healthyMeal: .healthyMeal(body)
        case .cheatMeal, .disclaimer: .cheatMeal(body)
        }
    }
}

/// The cover large, and with more than one photo, a row to pick which is the cover. With no
/// photo, the character stands in.
private struct MediaBlock: View {
    @Environment(\.sceneTheme) private var theme
    let model: TodayModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let cover = model.photos.first {
                PhotoImage(photo: cover)
                    // Wider than tall, so the sport row and the caption fit below it on one screen.
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .accessibilityElement()
                    .accessibilityLabel(Text("封面", bundle: .module))
                    .accessibilityIdentifier("compose.cover")
            }
            if model.photos.count > 1 {
                HStack(spacing: Space.xs) {
                    ForEach(Array(model.photos.enumerated()), id: \.element.id) { index, photo in
                        CoverChoice(photo: photo, number: index + 1, isCover: index == 0) {
                            model.makeCover(photo)
                        }
                    }
                }
            }
        }
    }
}

/// A thumbnail that becomes the cover when tapped. The cover is ringed and labelled 封面.
private struct CoverChoice: View {
    @Environment(\.sceneTheme) private var theme
    let photo: PreparedPhoto
    let number: Int
    let isCover: Bool
    let action: () -> Void

    private let side: Double = 64

    var body: some View {
        Button(action: action) {
            PhotoImage(photo: photo)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: Radius.pick, style: .continuous))
                .overlay {
                    if isCover {
                        RoundedRectangle(cornerRadius: Radius.pick, style: .continuous)
                            .strokeBorder(Color(role: .bgBrand, in: theme), lineWidth: Sizing.selectionStroke)
                    }
                }
                .overlay(alignment: .bottom) {
                    if isCover {
                        Text("封面", bundle: .module)
                            .typeStyle(TypeRamp.label)
                            .foregroundStyle(Color(role: .fgOnBrand, in: theme))
                            .padding(.horizontal, Space.xs)
                            .background(Color(role: .bgBrand, in: theme), in: Capsule())
                            .padding(.bottom, Space.xxs)
                    }
                }
        }
        .buttonStyle(PressableButtonStyle())
        .haptic(.pick, trigger: isCover)
        .accessibilityLabel(Text("第 \(number) 张照片", bundle: .module))
        .accessibilityHint(isCover ? Text(verbatim: "") : Text("设为封面", bundle: .module))
        .accessibilityAddTraits(isCover ? .isSelected : [])
        .accessibilityIdentifier("compose.photo.\(number)")
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
    private static let quickPicks = [15, 30, 45, 60, 90]
}
#endif
