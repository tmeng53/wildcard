#if os(iOS)
import AvatarUI
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// 今日请假条 (spec rev 186, section 1, made calmer 2026-11-06): the excuse is the page's one
/// line, in the middle of the page, and tapping it edits it. Above the button, one row: the four
/// styles and 编一句, which puts a line from the member's own words in the picked style in its
/// place; then 换一句 shows the next. The writer answers three lines at a time, so only every
/// third 换一句 (or a new style or new words) asks it again, and typing and picking a style cost
/// nothing. Up to `Disclaimer.maxLength` characters.
struct DisclaimerComposer: View {

    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: TodayModel
    @State private var text = ""
    @State private var entry = DisclaimerEntry()
    @State private var style = DisclaimerStyle.funny
    /// The writer's last three lines, shown one at a time.
    @State private var drafts: [String] = []
    /// The next of `drafts` 换一句 shows; past the end, it asks the writer again.
    @State private var next = 0
    /// The words and style the lines on offer were written from; nil for random lines.
    @State private var draftsFrom: Origin?
    @State private var isWriting = false
    /// Counts lines that landed in the hero, for their haptic.
    @State private var landed = 0
    /// Whether the squad sees it: on until the member turns it off.
    @State private var isShared = true
    /// The past day it counts for (补打卡); nil is today, whatever day it is when it posts. It
    /// opens on today, or on the latest day before it without a 练了 when today can't take one.
    @State private var day: LocalDay?
    @FocusState private var isEditing: Bool

    init(model: TodayModel) {
        self.model = model
        let blocked = model.blockedForDisclaimer
        let today = model.disclaimerDays.last
        let latest = model.disclaimerDays.last { !blocked.contains($0) }
        _day = State(initialValue: latest == today ? nil : latest)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclaimerHeader(model: model, day: $day)
                .padding(.bottom, Space.l)
            // The excuse sits in the middle of the room the choices leave.
            Spacer(minLength: 0)
            hero
            Spacer(minLength: Space.l)
            if entry.isBlocked {
                CareLine()
                    .padding(.bottom, Space.m)
            } else {
                choices
            }
            if model.sendFailed {
                Text("没发出去，再点一次打卡", bundle: .module)
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .padding(.bottom, Space.xs)
            }
            if let squad = model.shareSquad {
                ShareRow(squad: squad, isShared: $isShared)
                    .padding(.bottom, Space.xs)
            }
            // The page's last line, over nothing else: it floats, in glass.
            PostButton(model: model, disclaimer: entry.disclaimer, isShared: isShared, day: day)
                .controlPlacement(.floating)
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.xs)
        .padding(.bottom, Space.xs)
        .background(Color(role: .bgSubtle, in: theme).ignoresSafeArea())
        .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: entry)
        .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: drafts)
        .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: isEditing)
        .haptic(.appear, trigger: landed)
        .task {
            // Before the member types, 编一句 shows dice lines.
            drafts = DiceDisclaimerWriter.rollDefault(3)
            // Writing the reason comes first: the page opens with the keyboard up.
            isEditing = true
        }
    }

    /// The excuse: the field itself, so tapping it edits it.
    private var hero: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            TextField(text: $text, axis: .vertical) {
                Text("为什么没练？", bundle: .module)
            }
            .typeStyle(TypeRamp.title)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .lineLimit(1...4)
            .focused($isEditing)
            .submitLabel(.done)
            .opacity(isWriting ? Loading.waitingOpacity : 1)
            .animation(.wildcard(Motion.fadeIn), value: isWriting)
            .accessibilityIdentifier("disclaimer.field")
            .onChange(of: text) { _, typed in
                // Return finishes editing; the excuse is one line of at most `Disclaimer.maxLength` characters.
                if typed.contains(where: \.isNewline) { isEditing = false }
                let fitted = DisclaimerEntry.fit(typed)
                if fitted != typed { text = fitted }
                // A line the writer put in is already the entry's; anything else the member typed.
                guard fitted != entry.text else { return }
                entry.write(fitted)
                // Lines from older words don't answer the new ones.
                drafts = []
                next = 0
            }
            // The count while typing; otherwise 用回我写的 once a line replaced the member's words.
            Group {
                if isEditing {
                    Text(verbatim: "\(entry.text.count)/\(Disclaimer.maxLength)")
                        .typeStyle(TypeRamp.label)
                        .foregroundStyle(Color(role: .fgSubtle, in: theme))
                        .monospacedDigit()
                        .accessibilityIdentifier("disclaimer.count")
                } else if entry.canRestore {
                    Button {
                        entry.restore()
                        text = entry.text
                    } label: {
                        Label {
                            Text("用回我写的", bundle: .module)
                        } icon: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .frame(minHeight: Sizing.minimumTapTarget)
                    }
                    .accessibilityIdentifier("disclaimer.restore")
                }
            }
            .frame(minHeight: Sizing.minimumTapTarget, alignment: .leading)
        }
    }

    /// The styles and the button that puts a line up, on one row where it fits (else the button
    /// goes under the styles). Hidden while the member types, so the keyboard leaves room.
    @ViewBuilder private var choices: some View {
        if !isEditing {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.xs) {
                    styles
                    Spacer(minLength: 0)
                    write
                }
                VStack(alignment: .leading, spacing: Space.xxs) {
                    styles
                    write
                }
            }
            .padding(.bottom, Space.s)
            .transition(.opacity)
        }
    }

    /// The four styles as pills, the picked one marked. Picking only picks: it asks nothing.
    private var styles: some View {
        HStack(spacing: Space.xs) {
            ForEach(DisclaimerStyle.allCases, id: \.self) { option in
                PickPill(option.label, isSelected: option == style) {
                    style = option
                }
                .disabled(isWriting)
                .accessibilityIdentifier("disclaimer.style.\(option.rawValue)")
            }
        }
    }

    private var write: some View {
        WriteButton(isAgain: draftsAnswer && next > 0, isWriting: isWriting) {
            Task { await showNext() }
        }
    }

    /// Puts a line in the hero.
    private func take(_ line: String) {
        entry.suggest(line)
        text = entry.text
        landed += 1
    }

    /// Where the lines on offer came from: the member's words and a style.
    private struct Origin: Equatable {
        let words: String
        let style: DisclaimerStyle
    }

    /// The writer's lines answer the words and style on screen, so 换一句 can show the next one.
    private var draftsAnswer: Bool {
        guard !drafts.isEmpty else { return false }
        guard let draftsFrom else { return entry.mine.isEmpty }
        return draftsFrom == Origin(words: entry.mine, style: style)
    }

    /// The next of the writer's lines, or, once they ran out or answer other words or another
    /// style, three new ones, the first of them at once.
    private func showNext() async {
        if draftsAnswer, drafts.indices.contains(next) {
            take(drafts[next])
            next += 1
            return
        }
        let asked = Origin(words: entry.mine, style: style)
        let lines = await fetch(style: asked.style)
        guard let first = lines.first else { return }
        drafts = Array(lines.prefix(3))
        draftsFrom = asked.words.isEmpty ? nil : asked
        next = 1
        take(first)
    }

    /// Up to three new lines, none of them the ones just offered: from the member's own words, or
    /// at random when they typed none, topped up with dice lines when the writer has too few new ones.
    private func fetch(style: DisclaimerStyle) async -> [String] {
        let shown = Set(drafts + [entry.text])
        let spare = DiceDisclaimerWriter.rollAll()
        let reason = entry.mine.trimmingCharacters(in: .whitespaces)
        guard !reason.isEmpty else { return DisclaimerEntry.newLines(from: [], spare: spare, shown: shown) }
        isWriting = true
        defer { isWriting = false }
        let result = await model.suggestions(for: reason, style: style)
        // The member may have typed while the writer worked; its answer is about the old words.
        guard entry.mine.trimmingCharacters(in: .whitespaces) == reason else { return [] }
        switch result {
        case .drafts(let lines):
            return DisclaimerEntry.newLines(from: lines, spare: spare, shown: shown)
        case .blocked:
            entry.block()
            text = entry.text
            isEditing = false
            return []
        }
    }
}

/// The generate button: 编一句 before a line from the member's words and style is up, 换一句
/// after; it is the only thing that asks the writer. A white capsule outlined in ink, so it reads
/// before the style pills beside it.
private struct WriteButton: View {
    @Environment(\.sceneTheme) private var theme
    let isAgain: Bool
    let isWriting: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                if isAgain {
                    Text("换一句", bundle: .module)
                } else {
                    Text("编一句", bundle: .module)
                }
            } icon: {
                // While the writer works, 三拍 in the icon's place (loader design A).
                LoadingSwap(isWriting) {
                    Image(systemName: isAgain ? "arrow.clockwise" : "wand.and.sparkles")
                }
            }
        }
        .buttonStyle(SecondaryButtonStyle(.inCard))
        .overlay {
            Capsule()
                .strokeBorder(Color(role: .fgDefault, in: theme), lineWidth: Sizing.selectionStroke)
                .allowsHitTesting(false)
        }
        .fixedSize()
        .disabled(isWriting)
        .accessibilityIdentifier("disclaimer.write")
    }
}

/// The page's one primary button.
private struct PostButton: View {
    let model: TodayModel
    /// The excuse to post, or nil while it can't be.
    let disclaimer: Disclaimer?
    let isShared: Bool
    let day: LocalDay?

    var body: some View {
        Button {
            guard let disclaimer, !model.isSending else { return }
            Task { await model.post(.disclaimer(disclaimer), shared: isShared, on: day) }
        } label: {
            Text("发布请假条", bundle: .module)
                .loadingLabel(model.isSending)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
        // Still enabled while sending, so it stays the brand color under its dots; the action
        // ignores taps until the post is done.
        .disabled(disclaimer == nil)
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
