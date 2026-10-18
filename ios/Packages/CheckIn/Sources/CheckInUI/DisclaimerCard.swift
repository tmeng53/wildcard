#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// 今日免责声明 (spec rev 186, section 1): a glass card over the scene. Type the reason and let
/// the writer turn it into three lines, or roll the dice; up to 40 characters; 打卡.
struct DisclaimerCard: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: TodayModel
    @State private var text = ""
    @State private var drafts: [String] = []
    @State private var isBlocked = false
    @State private var isWriting = false
    @State private var rolls = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Text("今日免责声明", bundle: .module)
                    .typeStyle(TypeRamp.headline)
                    .foregroundStyle(Color(role: .textPrimary, in: theme))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    model.cancel()
                } label: {
                    Image(systemName: "xmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color(role: .textSecondary, in: theme))
                        .frame(width: Sizing.minimumTapTarget, height: Sizing.minimumTapTarget)
                }
                .accessibilityLabel(Text("关闭", bundle: .module))
                .accessibilityIdentifier("disclaimer.close")
            }

            VStack(alignment: .trailing, spacing: Space.xxs) {
                TextField(text: $text, axis: .vertical) {
                    Text("编个借口吧…", bundle: .module)
                }
                .typeStyle(TypeRamp.field)
                .lineLimit(1...3)
                .padding(Sizing.fieldInset)
                .background(Color(Palette.white).opacity(0.7), in: RoundedRectangle(cornerRadius: Radius.s))
                .onChange(of: text) { _, typed in
                    let fitted = Self.fit(typed)
                    if fitted != typed { text = fitted }
                }
                .accessibilityIdentifier("disclaimer.field")
                if text.count >= Disclaimer.maxLength - 10 {
                    Text(verbatim: "\(text.count)/\(Disclaimer.maxLength)")
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .textTertiary, in: theme))
                        .monospacedDigit()
                }
            }

            HStack(spacing: Sizing.pillGap) {
                ChoicePill(Text("帮我写", bundle: .module), systemImage: "sparkles", isSelected: false) {
                    Task { await write() }
                }
                .disabled(isWriting || text.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("disclaimer.write")
                ChoicePill(Text("换一个", bundle: .module), systemImage: "dice", isSelected: false) {
                    roll()
                }
                .accessibilityIdentifier("disclaimer.dice")
                if isWriting {
                    Text("正在编借口…", bundle: .module)
                        .typeStyle(TypeRamp.caption)
                        .foregroundStyle(Color(role: .textSecondary, in: theme))
                }
            }

            if isBlocked {
                CareLine()
            } else if !drafts.isEmpty {
                VStack(spacing: Space.xs) {
                    ForEach(Array(drafts.enumerated()), id: \.offset) { index, draft in
                        DraftChoice(line: draft, isSelected: draft == text) { text = draft }
                            .accessibilityIdentifier("disclaimer.draft.\(index + 1)")
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }

            Button {
                guard let disclaimer = try? Disclaimer(text) else { return }
                Task { await model.post(.disclaimer(disclaimer)) }
            } label: {
                Group {
                    if model.isSending {
                        ProgressView()
                    } else {
                        Text("打卡", bundle: .module).typeStyle(TypeRamp.action)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.isSending || (try? Disclaimer(text)) == nil)
            .accessibilityIdentifier("disclaimer.post")

            if model.sendFailed {
                Text("没发出去，再点一次打卡", bundle: .module)
                    .typeStyle(TypeRamp.caption)
                    .foregroundStyle(Color(role: .textSecondary, in: theme))
            }
        }
        .padding(Space.m)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .animation(.wildcard(Motion.panel, reduceMotion: reduceMotion), value: drafts)
        .animation(.wildcard(Motion.snappy, reduceMotion: reduceMotion), value: isBlocked)
        .sensoryFeedback(.selection, trigger: rolls)
    }

    private func write() async {
        isWriting = true
        defer { isWriting = false }
        switch await model.suggestions(for: text) {
        case .drafts(let lines):
            isBlocked = false
            let fitted = lines.map(Self.fit).filter { !$0.isEmpty }
            drafts = fitted.isEmpty ? DiceDisclaimerWriter.rollDefault(3) : Array(fitted.prefix(3))
        case .blocked:
            drafts = []
            isBlocked = true
        }
    }

    private func roll() {
        rolls += 1
        isBlocked = false
        drafts = []
        text = DiceDisclaimerWriter.rollDefault(1).first ?? text
    }

    /// One line, at most `Disclaimer.maxLength` characters.
    private static func fit(_ text: String) -> String {
        String(text.filter { !$0.isNewline }.prefix(Disclaimer.maxLength))
    }
}

/// A line the writer offered. Tapping it puts it in the field, where it can still be edited.
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
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.s)
                .background(Color(Palette.white).opacity(0.7), in: RoundedRectangle(cornerRadius: Radius.s))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Radius.s)
                            .strokeBorder(Color(role: .signature, in: theme), lineWidth: 2)
                    }
                }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// What the author alone sees when the reason touches self-harm: no joke, a gentle line and a
/// help line (spec section 3). Copy pending from the spec thread.
private struct CareLine: View {
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("这句我们不帮你编了。最近要是很难受，找人聊聊会好一点。", bundle: .module)
                .typeStyle(TypeRamp.callout)
                .foregroundStyle(Color(role: .textPrimary, in: theme))
            if let url = URL(string: "https://988lifeline.org") {
                Link(destination: url) {
                    Text("988 心理援助热线", bundle: .module)
                        .typeStyle(TypeRamp.calloutEmphasis)
                        .foregroundStyle(Color(role: .signatureText, in: theme))
                }
            }
        }
        .accessibilityIdentifier("disclaimer.care")
    }
}
#endif
