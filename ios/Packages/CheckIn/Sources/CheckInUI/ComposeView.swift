#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// One page like a social app's new post (spec rev 186, section 1): 取消 / title / 发布, the
/// photos with their cover, the sport for a 练了, and a line up to 60 characters. No minutes,
/// no meal type.
struct ComposeView: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: TodayModel
    let meaning: Meaning
    @State private var caption = ""
    @FocusState private var isWriting: Bool
    @State private var activity: Activity?
    @State private var isPickingSport = false

    var body: some View {
        VStack(spacing: 0) {
            bar
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.l) {
                        MediaBlock(model: model)
                        if meaning == .trained {
                            SportRow(selected: currentActivity, isPickingSport: $isPickingSport) { activity = $0 }
                        }
                        captionField.id(Self.captionID)
                        if model.sendFailed {
                            Text("没发出去，再点一次发布", bundle: .module)
                                .typeStyle(TypeRamp.caption)
                                .foregroundStyle(Color(role: .textSecondary, in: theme))
                                .accessibilityIdentifier("compose.failed")
                        }
                    }
                    .padding(.horizontal, Space.gutter)
                    .padding(.vertical, Space.m)
                }
                .scrollDismissesKeyboard(.interactively)
                // Keep the line being written above the keyboard.
                .onChange(of: isWriting) { _, writing in
                    guard writing else { return }
                    withAnimation(.wildcard(Motion.smooth, reduceMotion: reduceMotion)) {
                        proxy.scrollTo(Self.captionID, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(role: .canvas, in: theme).ignoresSafeArea())
        .sheet(isPresented: $isPickingSport) {
            SportPicker(selected: currentActivity) { picked in
                activity = picked
                isPickingSport = false
            }
            .environment(\.sceneTheme, theme)
        }
    }

    private static let captionID = "caption"

    /// The board's last sport until the member picks one; detection from the cover comes later.
    private var currentActivity: Activity {
        activity ?? model.board?.lastActivity ?? .sport(.run)
    }

    private var bar: some View {
        HStack {
            Button {
                model.cancel()
            } label: {
                Text("取消", bundle: .module)
                    .typeStyle(TypeRamp.body)
                    .foregroundStyle(Color(role: .textPrimary, in: theme))
                    .frame(minHeight: Sizing.minimumTapTarget)
            }
            .accessibilityIdentifier("compose.cancel")
            Spacer()
            Button {
                Task { await model.post(draft) }
            } label: {
                if model.isSending {
                    ProgressView()
                } else {
                    Text("发布", bundle: .module)
                        .typeStyle(TypeRamp.headline)
                        .foregroundStyle(Color(role: .signatureText, in: theme))
                }
            }
            .frame(minHeight: Sizing.minimumTapTarget)
            .disabled(model.isSending)
            .accessibilityIdentifier("compose.post")
        }
        .overlay {
            meaning.fullName
                .typeStyle(TypeRamp.headline)
                .foregroundStyle(Color(role: .textPrimary, in: theme))
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, Space.xxs)
    }

    private var captionField: some View {
        VStack(alignment: .trailing, spacing: Space.xxs) {
            TextField(text: $caption, axis: .vertical) {
                placeholder
            }
            .typeStyle(TypeRamp.field)
            .lineLimit(1...4)
            .focused($isWriting)
            .onChange(of: caption) { _, typed in
                let fitted = PostBody.fitCaption(typed)
                if fitted != typed { caption = fitted }
            }
            .accessibilityIdentifier("compose.caption")
            // The count shows only near the limit, so the field stays quiet.
            if caption.count >= PostBody.captionLimit - 10 {
                Text(verbatim: "\(caption.count)/\(PostBody.captionLimit)")
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .textTertiary, in: theme))
                    .monospacedDigit()
            }
        }
    }

    private var placeholder: Text {
        switch meaning {
        case .trained: Text("炫耀一下成果…", bundle: .module)
        case .fresh: Text("这顿很自律…", bundle: .module)
        case .indulgence, .disclaimer: Text("坦白从宽…", bundle: .module)
        }
    }

    private var draft: CheckInDraft {
        let body = PostBody(photos: model.photos, caption: caption)
        return switch meaning {
        case .trained: .trained(currentActivity, body)
        case .fresh: .healthyMeal(body)
        case .indulgence, .disclaimer: .cheatMeal(body)
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
                    .clipShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
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
                .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                .overlay {
                    if isCover {
                        RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                            .strokeBorder(Color(role: .signature, in: theme), lineWidth: Sizing.selectionStroke * 1.5)
                    }
                }
                .overlay(alignment: .bottom) {
                    if isCover {
                        Text("封面", bundle: .module)
                            .typeStyle(TypeRamp.footnote)
                            .foregroundStyle(Color(role: .onSignature, in: theme))
                            .padding(.horizontal, Space.xs)
                            .background(Color(role: .signature, in: theme), in: Capsule())
                            .padding(.bottom, Space.xxs)
                    }
                }
        }
        .buttonStyle(PressableButtonStyle())
        .sensoryFeedback(.selection, trigger: isCover)
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
                HStack(spacing: Sizing.pillGap) {
                    ForEach(choices, id: \.key) { activity in
                        ChoicePill(activity.name, systemImage: activity.symbol, isSelected: activity == selected) {
                            pick(activity)
                        }
                        .accessibilityIdentifier("compose.sport.\(activity.key)")
                    }
                    ChoicePill(Text("更多", bundle: .module), systemImage: "ellipsis", isSelected: false) {
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
        [selected] + Sport.quickPicks.map(Activity.sport).filter { $0 != selected }
    }
}
#endif
