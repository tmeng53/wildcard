#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// 今日免责声明 (spec rev 186, section 1): a glass card over the scene. The line is the hero,
/// written straight onto the card in large type like a new post, with × and 打卡 in the same
/// places as the compose page's 取消 and 发布. One ✨ button offers lines in a row of chips
/// above the keyboard: from the typed reason, or at random when there is none. Up to 40
/// characters.
struct DisclaimerCard: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: TodayModel
    @State private var text = ""
    @State private var entry = DisclaimerEntry()
    @State private var drafts: [String] = []
    @State private var isWriting = false
    @State private var batches = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            bar

            VStack(alignment: .trailing, spacing: Space.xxs) {
                TextField(text: $text, axis: .vertical) {
                    Text("编个借口吧…", bundle: .module)
                }
                .typeStyle(TypeRamp.title)
                .foregroundStyle(Color(role: .textPrimary, in: theme))
                .lineLimit(1...3)
                .accessibilityIdentifier("disclaimer.field")
                .onChange(of: text) { _, typed in
                    // The field shows exactly what will be posted: no newlines, at most 40 characters.
                    let fitted = DisclaimerEntry.fit(typed)
                    if fitted != typed { text = fitted }
                    entry.write(fitted)
                }
                if entry.text.count >= Disclaimer.maxLength - 10 {
                    Text(verbatim: "\(entry.text.count)/\(Disclaimer.maxLength)")
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .textTertiary, in: theme))
                        .monospacedDigit()
                }
            }

            if entry.isBlocked {
                CareLine()
            } else {
                suggestions
            }

            if model.sendFailed {
                Text("没发出去，再点一次打卡", bundle: .module)
                    .typeStyle(TypeRamp.caption)
                    .foregroundStyle(Color(role: .textSecondary, in: theme))
            }
        }
        .padding(Space.m)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .animation(.wildcard(Motion.panel, reduceMotion: reduceMotion), value: drafts)
        .animation(.wildcard(Motion.snappy, reduceMotion: reduceMotion), value: entry.isBlocked)
        .sensoryFeedback(.selection, trigger: batches)
    }

    /// × on the left, the title in the middle, 打卡 on the right: the compose page's layout.
    private var bar: some View {
        HStack {
            Button {
                model.cancel()
            } label: {
                Image(systemName: "xmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(role: .textSecondary, in: theme))
                    .frame(width: Sizing.minimumTapTarget, height: Sizing.minimumTapTarget, alignment: .leading)
            }
            .accessibilityLabel(Text("关闭", bundle: .module))
            .accessibilityIdentifier("disclaimer.close")
            Spacer()
            Button {
                guard let disclaimer = entry.disclaimer else { return }
                Task { await model.post(.disclaimer(disclaimer)) }
            } label: {
                if model.isSending {
                    ProgressView()
                } else {
                    Text("打卡", bundle: .module)
                        .typeStyle(TypeRamp.headline)
                        .foregroundStyle(
                            Color(role: entry.disclaimer == nil ? .textTertiary : .signatureText, in: theme))
                }
            }
            .frame(minHeight: Sizing.minimumTapTarget)
            .disabled(model.isSending || entry.disclaimer == nil)
            .accessibilityIdentifier("disclaimer.post")
        }
        .overlay {
            Text("今日免责声明", bundle: .module)
                .typeStyle(TypeRamp.headline)
                .foregroundStyle(Color(role: .textPrimary, in: theme))
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// ✨ and the lines it offered, in one row that scrolls sideways.
    private var suggestions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Sizing.pillGap) {
                ChoicePill(
                    isWriting ? Text("正在编借口…", bundle: .module) : Text("帮我写", bundle: .module),
                    systemImage: "sparkles", isSelected: false
                ) {
                    Task { await write() }
                }
                .disabled(isWriting)
                .accessibilityIdentifier("disclaimer.write")
                ForEach(Array(drafts.enumerated()), id: \.offset) { index, draft in
                    DraftChoice(line: draft, isSelected: draft == entry.text) { text = draft }
                        .accessibilityIdentifier("disclaimer.draft.\(index + 1)")
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .scrollClipDisabled()
    }

    /// Lines from the typed reason, or three at random when nothing is typed yet.
    private func write() async {
        batches += 1
        let reason = entry.text.trimmingCharacters(in: .whitespaces)
        guard !reason.isEmpty else {
            drafts = DiceDisclaimerWriter.rollDefault(3)
            return
        }
        isWriting = true
        defer { isWriting = false }
        switch await model.suggestions(for: reason) {
        case .drafts(let lines):
            let fitted = lines.map(DisclaimerEntry.fit).filter { !$0.isEmpty }
            drafts = fitted.isEmpty ? DiceDisclaimerWriter.rollDefault(3) : Array(fitted.prefix(3))
        case .blocked:
            drafts = []
            entry.block()
        }
    }
}

/// A line the writer offered, as a chip. Tapping it puts it in the field, where it can still
/// be edited.
private struct DraftChoice: View {
    @Environment(\.sceneTheme) private var theme
    let line: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: line)
                .typeStyle(TypeRamp.callout)
                .foregroundStyle(Color(role: .textPrimary, in: theme))
                .lineLimit(1)
                .padding(.horizontal, Space.s)
                .frame(minHeight: Sizing.minimumTapTarget)
                .background(Color(Palette.white).opacity(0.7), in: Capsule())
                .overlay {
                    if isSelected {
                        Capsule().strokeBorder(Color(role: .signature, in: theme), lineWidth: 2)
                    }
                }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// What the author alone sees when the reason reads as self-harm (spec section 3): no joke, a
/// gentle line, and the 988 line to call or text. Teammates see nothing.
private struct CareLine: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        // Every line of the care copy shows in full, even with the keyboard up: none of it may
        // be cut to an ellipsis.
        VStack(alignment: .leading, spacing: Space.s) {
            Text("这条先不写段子了。最近要是真的很难，找个人聊聊吧。", bundle: .module)
                .typeStyle(TypeRamp.callout)
                .foregroundStyle(Color(role: .textPrimary, in: theme))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Sizing.pillGap) {
                ChoicePill(Text("打给 988", bundle: .module), systemImage: "phone", isSelected: false) {
                    open("tel:988")
                }
                .accessibilityIdentifier("disclaimer.care.call")
                ChoicePill(Text("发短信给 988", bundle: .module), systemImage: "message", isSelected: false) {
                    open("sms:988")
                }
                .accessibilityIdentifier("disclaimer.care.text")
            }
            Text("美国和加拿大都能拨 988，24 小时，免费。美国的线路可以要中文翻译。", bundle: .module)
                .typeStyle(TypeRamp.caption)
                .foregroundStyle(Color(role: .textSecondary, in: theme))
                .fixedSize(horizontal: false, vertical: true)
            Text("有紧急危险请直接打 911。", bundle: .module)
                .typeStyle(TypeRamp.caption)
                .foregroundStyle(Color(role: .textSecondary, in: theme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("disclaimer.care")
    }

    private func open(_ address: String) {
        guard let url = URL(string: address) else { return }
        openURL(url)
    }
}
#endif
