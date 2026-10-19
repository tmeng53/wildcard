#if os(iOS)
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// 今日免责声明 (spec rev 186, section 1), laid out like an editorial page: the excuse itself is
/// the hero, in large type at the left, and tapping it edits it. Below it, the four styles as a
/// row of text tabs and three lines in the picked style, each from the member's own words or at
/// random when they typed none; picking a style or a line puts it in the hero at once. One
/// solid button posts. Up to 40 characters.
struct DisclaimerComposer: View {
    private static let tabUnderline: Double = 2

    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: TodayModel
    @State private var text = ""
    @State private var entry = DisclaimerEntry()
    @State private var style: DisclaimerStyle?
    /// The three lines on offer.
    @State private var drafts: [String] = []
    @State private var isWriting = false
    /// Counts lines that landed in the hero, for their haptic.
    @State private var landed = 0
    @FocusState private var isEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, Space.xl)
            hero
                .padding(.bottom, Space.l)
            if entry.isBlocked {
                CareLine()
                    .padding(.bottom, Space.m)
            } else {
                choices
            }
            // The room left over gathers above the button, not between the groups.
            Spacer(minLength: 0)
            if model.sendFailed {
                Text("没发出去，再点一次打卡", bundle: .module)
                    .typeStyle(TypeRamp.caption)
                    .foregroundStyle(Color(role: .textSecondary, in: theme))
                    .padding(.bottom, Space.xs)
            }
            PostButton(model: model, disclaimer: entry.disclaimer)
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.xs)
        .padding(.bottom, Space.xs)
        .background(Color(role: .surface, in: theme).ignoresSafeArea())
        .animation(.wildcard(Motion.snappy, reduceMotion: reduceMotion), value: entry)
        .animation(.wildcard(Motion.snappy, reduceMotion: reduceMotion), value: drafts)
        .animation(.wildcard(Motion.snappy, reduceMotion: reduceMotion), value: isEditing)
        .sensoryFeedback(.selection, trigger: style)
        .sensoryFeedback(.impact(weight: .light), trigger: landed)
        .task {
            drafts = DiceDisclaimerWriter.rollDefault(3)
            // Writing the reason comes first: the page opens with the keyboard up.
            isEditing = true
        }
    }

    /// Today's date and the page's name, small; × on the right.
    private var header: some View {
        HStack(spacing: Space.s) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Date.now, format: .dateTime.month(.defaultDigits).day().weekday(.abbreviated))
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .textPrimary, in: theme))
                Text("今日免责声明", bundle: .module)
                    .typeStyle(TypeRamp.sectionLabel)
                    .foregroundStyle(Color(role: .textSecondary, in: theme))
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            Button {
                model.cancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: Sizing.pillGlyph, weight: .medium))
                    .foregroundStyle(Color(role: .textPrimary, in: theme))
                    .frame(width: Sizing.minimumTapTarget, height: Sizing.minimumTapTarget, alignment: .trailing)
            }
            .accessibilityLabel(Text("关闭", bundle: .module))
            .accessibilityIdentifier("disclaimer.close")
        }
    }

    /// The excuse in large type: the field itself, so tapping it edits it.
    private var hero: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            TextField(text: $text, axis: .vertical) {
                Text("为什么没练？", bundle: .module)
            }
            .typeStyle(TypeRamp.hero)
            .foregroundStyle(Color(role: .textPrimary, in: theme))
            .lineLimit(1...4)
            .focused($isEditing)
            .opacity(isWriting ? 0.4 : 1)
            .accessibilityIdentifier("disclaimer.field")
            .onChange(of: text) { _, typed in
                // Return finishes editing; the excuse is one line of at most 40 characters.
                if typed.contains(where: \.isNewline) { isEditing = false }
                let fitted = DisclaimerEntry.fit(typed)
                if fitted != typed { text = fitted }
                // A line the writer put in is already the entry's; anything else the member typed.
                guard fitted != entry.text else { return }
                entry.write(fitted)
            }
            HStack(spacing: Space.s) {
                // The count while typing; otherwise 编辑, which starts typing.
                if isEditing {
                    Text(verbatim: "\(entry.text.count)/\(Disclaimer.maxLength)")
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .textTertiary, in: theme))
                        .monospacedDigit()
                        .accessibilityIdentifier("disclaimer.count")
                } else {
                    Button {
                        isEditing = true
                    } label: {
                        Text("编辑", bundle: .module)
                            .typeStyle(TypeRamp.footnote)
                            .foregroundStyle(Color(role: .textSecondary, in: theme))
                            .frame(minHeight: Sizing.minimumTapTarget)
                    }
                    .accessibilityIdentifier("disclaimer.edit")
                }
                if entry.canRestore {
                    Button {
                        entry.restore()
                        text = entry.text
                    } label: {
                        Text("用回我写的", bundle: .module)
                            .typeStyle(TypeRamp.footnote)
                            .foregroundStyle(Color(role: .textSecondary, in: theme))
                            .underline()
                            .frame(minHeight: Sizing.minimumTapTarget)
                    }
                    .accessibilityIdentifier("disclaimer.restore")
                }
            }
            .frame(minHeight: Sizing.minimumTapTarget)
        }
    }

    /// What the lines are made from, the style tabs, the three lines and 换一组. Out of the way
    /// while the member types, so the keyboard leaves room for the excuse.
    @ViewBuilder private var choices: some View {
        VStack(alignment: .leading, spacing: 0) {
            source
                .padding(.bottom, Space.xxs)
            tabs
            if !isEditing {
                ForEach(Array(drafts.enumerated()), id: \.element) { index, draft in
                    DraftRow(line: draft, isPicked: draft == entry.text) { take(draft) }
                        .accessibilityIdentifier("disclaimer.draft.\(index + 1)")
                }
                Button {
                    Task { await refill(style: style) }
                } label: {
                    Label {
                        Text("换一组", bundle: .module)
                    } icon: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .typeStyle(TypeRamp.caption)
                    .foregroundStyle(Color(role: .textSecondary, in: theme))
                    .frame(minHeight: Sizing.minimumTapTarget)
                }
                .disabled(isWriting)
                .accessibilityIdentifier("disclaimer.again")
            }
        }
        .padding(.bottom, Space.s)
    }

    /// 「灵感：deadline」, or 「灵感：随机」 before the member typed anything.
    private var source: some View {
        Group {
            if entry.mine.isEmpty {
                Text("灵感：随机", bundle: .module)
            } else {
                Text("灵感：\(entry.mine)", bundle: .module)
            }
        }
        .typeStyle(TypeRamp.caption)
        .foregroundStyle(Color(role: .textSecondary, in: theme))
        .lineLimit(1)
        .accessibilityIdentifier("disclaimer.source")
    }

    /// The four styles as text, the picked one underlined in the scene's color.
    private var tabs: some View {
        HStack(spacing: Space.l) {
            ForEach(DisclaimerStyle.allCases, id: \.self) { option in
                Button {
                    guard option != style else { return }
                    style = option
                    isEditing = false
                    Task { await refill(style: option) }
                } label: {
                    option.label
                        .typeStyle(TypeRamp.tileLabel)
                        .foregroundStyle(Color(role: option == style ? .textPrimary : .textSecondary, in: theme))
                        .frame(minHeight: Sizing.minimumTapTarget)
                        .overlay(alignment: .bottom) {
                            if option == style {
                                Rectangle()
                                    .fill(Color(role: .signature, in: theme))
                                    .frame(height: Self.tabUnderline)
                            }
                        }
                }
                .disabled(isWriting)
                .accessibilityAddTraits(option == style ? .isSelected : [])
                .accessibilityIdentifier("disclaimer.style.\(option.rawValue)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(role: .divider, in: theme)).frame(height: 1)
        }
    }

    /// Puts a line in the hero.
    private func take(_ line: String) {
        entry.suggest(line)
        text = entry.text
        landed += 1
    }

    /// Three new lines in `style`; picking a style is the rewrite itself, so the first lands in
    /// the hero at once.
    private func refill(style: DisclaimerStyle?) async {
        let lines = await fetch(style: style ?? .funny)
        guard !lines.isEmpty else { return }
        drafts = Array(lines.prefix(3))
        if style != nil, let first = drafts.first { take(first) }
    }

    /// Lines from the member's own words, or at random when they typed none. Lines already on
    /// offer aren't offered again.
    private func fetch(style: DisclaimerStyle) async -> [String] {
        let shown = Set(drafts + [entry.text])
        let reason = entry.mine.trimmingCharacters(in: .whitespaces)
        guard !reason.isEmpty else {
            return DiceDisclaimerWriter.rollDefault(DiceDisclaimerWriter.lines.count).filter { !shown.contains($0) }
        }
        isWriting = true
        defer { isWriting = false }
        let result = await model.suggestions(for: reason, style: style)
        // The member may have typed while the writer worked; its answer is about the old words.
        guard entry.mine.trimmingCharacters(in: .whitespaces) == reason else { return [] }
        switch result {
        case .drafts(let lines):
            let fitted = lines.map(DisclaimerEntry.fit).filter { !$0.isEmpty }
            return fitted.isEmpty ? DiceDisclaimerWriter.rollDefault(3) : fitted
        case .blocked:
            entry.block()
            isEditing = false
            return []
        }
    }
}

/// A line on offer: a row with a hairline under it, a dot in the scene's color once it's picked.
private struct DraftRow: View {
    private static let dot: Double = 6
    @Environment(\.sceneTheme) private var theme
    let line: String
    let isPicked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                Circle()
                    .fill(isPicked ? Color(role: .signature, in: theme) : .clear)
                    .frame(width: Self.dot, height: Self.dot)
                Text(verbatim: line)
                    .typeStyle(TypeRamp.callout)
                    .foregroundStyle(Color(role: isPicked ? .textPrimary : .textSecondary, in: theme))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, Space.s)
            .frame(minHeight: Sizing.minimumTapTarget)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color(role: .divider, in: theme)).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }
}

/// The one solid button: ink, so the excuse stays the page's hero.
private struct PostButton: View {
    @Environment(\.sceneTheme) private var theme
    let model: TodayModel
    /// The excuse to post, or nil while it can't be.
    let disclaimer: Disclaimer?

    var body: some View {
        Button {
            guard let disclaimer else { return }
            Task { await model.post(.disclaimer(disclaimer)) }
        } label: {
            ZStack {
                Text("发到小队", bundle: .module)
                    .opacity(model.isSending ? 0 : 1)
                if model.isSending { ProgressView().tint(Color(Palette.white)) }
            }
            .typeStyle(TypeRamp.headline)
            .foregroundStyle(Color(role: disclaimer == nil ? .textTertiary : .canvas, in: theme))
            .frame(maxWidth: .infinity, minHeight: Sizing.checkInHeight)
            .background(
                Color(role: disclaimer == nil ? .divider : .textPrimary, in: theme),
                in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(model.isSending || disclaimer == nil)
        .accessibilityIdentifier("disclaimer.post")
    }
}

extension DisclaimerStyle {
    /// The style's tab label.
    var label: Text {
        switch self {
        case .funny: Text("搞笑", bundle: .module)
        case .unhinged: Text("发疯", bundle: .module)
        case .heroic: Text("中二", bundle: .module)
        case .stubborn: Text("嘴硬", bundle: .module)
        }
    }
}

#endif
