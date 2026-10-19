#if os(iOS)
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// 今日免责声明 (spec rev 186, section 1): the member types straight into the speech bubble over
/// their character, so the line looks exactly as teammates will see it. A tray above the
/// keyboard holds the four styles, 「换一句」 and 打卡. Picking a style writes a line in it at
/// once, from the typed reason or at random when there is none; 「换一句」 gives another in the
/// same style; 「用回我写的」 brings the member's own words back. Up to 40 characters.
struct DisclaimerComposer: View {
    /// The tallest the character grows here; it shrinks first when the keyboard leaves less room.
    private static let figureHeight: Double = 180
    /// The narrowest the character shrinks to.
    private static let minimumFigureHeight: Double = 72
    /// The widest the bubble grows before its line wraps.
    private static let bubbleWidth: Double = 320
    private static let tail: Double = 10

    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: TodayModel
    @State private var text = ""
    @State private var entry = DisclaimerEntry()
    @State private var style: DisclaimerStyle?
    /// Lines the writer offered that haven't been shown yet, for the next 「换一句」.
    @State private var pending: [String] = []
    @State private var isWriting = false
    /// Counts lines that landed in the bubble, for their haptic.
    @State private var landed = 0

    var body: some View {
        VStack(spacing: 0) {
            bar
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.xs)
            Spacer(minLength: Space.s)
            bubble
            restoreSlot
            figure
            Spacer(minLength: Space.s)
            tray
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.xs)
        }
        .animation(.wildcard(Motion.snappy, reduceMotion: reduceMotion), value: entry)
        .animation(.wildcard(Motion.snappy, reduceMotion: reduceMotion), value: isWriting)
        .sensoryFeedback(.selection, trigger: style)
        .sensoryFeedback(.impact(weight: .light), trigger: landed)
    }

    /// × on the left, the title in the middle.
    private var bar: some View {
        HStack {
            Button {
                model.cancel()
            } label: {
                Image(systemName: "xmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(role: .textPrimary, in: theme))
                    .frame(width: Sizing.minimumTapTarget, height: Sizing.minimumTapTarget)
                    .glassEffect(.regular, in: Circle())
            }
            .accessibilityLabel(Text("关闭", bundle: .module))
            .accessibilityIdentifier("disclaimer.close")
            Spacer()
        }
        .overlay {
            Text("今日免责声明", bundle: .module)
                .typeStyle(TypeRamp.headline)
                .foregroundStyle(Color(role: .textSecondary, in: theme))
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// The field, drawn as the speech bubble the line lands in after posting.
    private var bubble: some View {
        TextField(text: $text, axis: .vertical) {
            Text("编个借口吧…", bundle: .module)
        }
        .typeStyle(TypeRamp.title)
        .foregroundStyle(Color(role: .textPrimary, in: theme))
        .multilineTextAlignment(.center)
        .lineLimit(1...3)
        .opacity(isWriting ? 0.4 : 1)
        .padding(.horizontal, Space.m)
        .padding(.top, Space.s)
        .padding(.bottom, Space.s + Self.tail)
        .background(BubbleShape(cornerRadius: Radius.l, tail: Self.tail).fill(Color(Palette.white)))
        .frame(maxWidth: Self.bubbleWidth)
        .padding(.horizontal, Space.gutter)
        .accessibilityIdentifier("disclaimer.field")
        .onChange(of: text) { _, typed in
            // The bubble shows exactly what will be posted: no newlines, at most 40 characters.
            let fitted = DisclaimerEntry.fit(typed)
            if fitted != typed { text = fitted }
            // A line the writer put in is already the entry's; anything else the member typed.
            guard fitted != entry.text else { return }
            entry.write(fitted)
            pending = []
        }
    }

    /// 「用回我写的」 under the bubble, once a suggested line replaced the member's words. The
    /// slot keeps its height, so the character doesn't jump.
    private var restoreSlot: some View {
        ZStack {
            if entry.canRestore {
                Button {
                    entry.restore()
                    text = entry.text
                    pending = []
                } label: {
                    Label {
                        Text("用回我写的", bundle: .module)
                    } icon: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .typeStyle(TypeRamp.caption)
                    .foregroundStyle(Color(role: .textSecondary, in: theme))
                    .padding(.horizontal, Space.s)
                    .frame(minHeight: Sizing.minimumTapTarget)
                }
                .accessibilityIdentifier("disclaimer.restore")
                .transition(.opacity)
            }
        }
        .frame(height: Sizing.minimumTapTarget)
    }

    @ViewBuilder private var figure: some View {
        if let player = model.player {
            CharacterView(player: player)
                .frame(minHeight: Self.minimumFigureHeight, maxHeight: Self.figureHeight)
                .accessibilityHidden(true)
        }
    }

    /// The styles, or the care line in their place; then 「换一句」, the count and 打卡.
    private var tray: some View {
        VStack(spacing: Space.s) {
            if entry.isBlocked {
                CareLine()
            } else {
                Picker(selection: styleSelection) {
                    ForEach(DisclaimerStyle.allCases, id: \.self) { style in
                        style.label.tag(Optional(style))
                    }
                } label: {
                    Text("风格", bundle: .module)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("disclaimer.style")
            }

            HStack(spacing: Space.s) {
                anotherButton
                Text(verbatim: "\(entry.text.count)/\(Disclaimer.maxLength)")
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .textTertiary, in: theme))
                    .monospacedDigit()
                    .accessibilityIdentifier("disclaimer.count")
                Button {
                    guard let disclaimer = entry.disclaimer else { return }
                    Task { await model.post(.disclaimer(disclaimer)) }
                } label: {
                    ZStack {
                        Text("打卡", bundle: .module).opacity(model.isSending ? 0 : 1)
                        if model.isSending { ProgressView() }
                    }
                    .typeStyle(TypeRamp.action)
                    .padding(.horizontal, Space.l)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.isSending || entry.disclaimer == nil)
                .accessibilityIdentifier("disclaimer.post")
            }

            if model.sendFailed {
                Text("没发出去，再点一次打卡", bundle: .module)
                    .typeStyle(TypeRamp.caption)
                    .foregroundStyle(Color(role: .textSecondary, in: theme))
            }
        }
        .padding(Space.s)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    /// 「换一句」: the next line in the picked style, the funny one before any is picked.
    private var anotherButton: some View {
        Button {
            Task { await another() }
        } label: {
            Label {
                Text("换一句", bundle: .module)
            } icon: {
                Image(systemName: "dice")
                    .foregroundStyle(Color(role: .meaningDisclaimer, in: theme))
            }
            .typeStyle(TypeRamp.calloutEmphasis)
            .foregroundStyle(Color(role: .meaningDisclaimerText, in: theme))
            .frame(maxWidth: .infinity, minHeight: Sizing.checkInHeight)
            .background(Color(role: .meaningDisclaimerWash, in: theme), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isWriting || entry.isBlocked)
        .accessibilityIdentifier("disclaimer.another")
    }

    /// Picking a style is the rewrite itself: a line in it lands at once.
    private var styleSelection: Binding<DisclaimerStyle?> {
        Binding {
            style
        } set: { picked in
            guard picked != style else { return }
            style = picked
            pending = []
            Task { await another() }
        }
    }

    /// Puts the next line in the bubble, asking the writer for more when none are left.
    private func another() async {
        if pending.isEmpty {
            pending = await fetch()
        }
        guard !pending.isEmpty else { return }
        entry.suggest(pending.removeFirst())
        text = entry.text
        landed += 1
    }

    /// Lines in the style from the member's own words, or at random when they typed none. A
    /// line already in the bubble isn't offered again.
    private func fetch() async -> [String] {
        let reason = entry.mine.trimmingCharacters(in: .whitespaces)
        guard !reason.isEmpty else {
            return DiceDisclaimerWriter.rollDefault(DiceDisclaimerWriter.lines.count).filter { $0 != entry.text }
        }
        isWriting = true
        defer { isWriting = false }
        let result = await model.suggestions(for: reason, style: style ?? .funny)
        // The member may have typed while the writer worked; its answer is about the old words.
        guard entry.mine.trimmingCharacters(in: .whitespaces) == reason else { return [] }
        switch result {
        case .drafts(let lines):
            let fitted = lines.map(DisclaimerEntry.fit).filter { !$0.isEmpty && $0 != entry.text }
            return fitted.isEmpty ? DiceDisclaimerWriter.rollDefault(3).filter { $0 != entry.text } : fitted
        case .blocked:
            entry.block()
            return []
        }
    }
}

extension DisclaimerStyle {
    /// The style's tab label.
    var label: Text {
        switch self {
        case .funny: Text("搞笑", bundle: .module)
        case .unhinged: Text("发疯", bundle: .module)
        case .poetic: Text("文艺", bundle: .module)
        case .stubborn: Text("嘴硬", bundle: .module)
        }
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
