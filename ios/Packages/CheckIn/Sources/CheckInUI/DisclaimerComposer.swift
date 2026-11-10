#if os(iOS)
import AvatarUI
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// 今日请假条 (spec rev 186, section 1; on the 入场券 since 2026-11-08), the same page as 发动态:
/// 取消 / title / 发布, then 请假｜休息, then the ticket: the excuse above its tear (up to
/// `Disclaimer.maxLength` characters, its count always showing) and, below it, 帮我编一句: the
/// four styles (a segmented control) and 编一句, which puts a line from the member's own words
/// in the picked style in its place; then 换一句 shows the next. The writer answers three lines at
/// a time, so only every third 换一句 (or a new style or new words) asks it again, and typing and
/// picking a style cost nothing. Under the ticket the 日期 strip (补打卡), whose days with a 练了
/// can't be picked; the title follows the day picked: 今日请假条 or 今日休息 for today, 请假条 or
/// 休息 before. Under 帮我编一句, the photos (up to three, the cover first) in a row with the W,
/// as a 训练's.
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
    /// 休息, a rest the member planned, rather than leave (请假): picked at the top.
    @State private var restDay = false
    @FocusState private var isEditing: Bool

    init(model: TodayModel) {
        self.model = model
        let blocked = model.blockedForDisclaimer
        let today = model.disclaimerDays.last
        let latest = model.disclaimerDays.last { !blocked.contains($0) }
        _day = State(initialValue: latest == today ? nil : latest)
    }

    var body: some View {
        VStack(spacing: 0) {
            ComposeBar(
                title: title, finish: Text(copy: "发布", bundle: .module), isWorking: model.isSending,
                canFinish: !model.isSending && disclaimer != nil && !(model.compose?.isPreparingPhotos ?? false),
                cancelID: "disclaimer.close", finishID: "disclaimer.post",
                cancel: { model.cancel() }, done: post)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    Picker(selection: $restDay) {
                        Text(copy: "请假", bundle: .module).tag(false)
                        Text(copy: "休息", bundle: .module).tag(true)
                    } label: {
                        Text(copy: "请假还是休息", bundle: .module)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("disclaimer.kind")
                    TicketCard {
                        face
                    } stub: {
                        if entry.isBlocked {
                            CareLine()
                        } else {
                            stub
                        }
                    }
                    if let today = model.disclaimerDays.last, model.disclaimerDays.count > 1 {
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            SectionLabel(Text(copy: "日期", bundle: .module))
                            DayPick(
                                days: model.disclaimerDays, blocked: model.blockedForDisclaimer,
                                picked: Binding {
                                    day ?? today
                                } set: {
                                    day = $0 == today ? nil : $0
                                })
                        }
                        .padding(.top, Space.xs)
                    }
                    if model.sendFailed {
                        Text(copy: "没发出去，再点一次发布", bundle: .module)
                            .typeStyle(TypeRamp.footnote)
                            .foregroundStyle(Color(role: .fgMuted, in: theme))
                    }
                }
                .padding(.horizontal, Space.pageMargin)
                .padding(.vertical, Space.m)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .actionBar(isShown: model.shareSquad != nil) {
            if let squad = model.shareSquad {
                ShareRow(squad: squad, isShared: $isShared)
            }
        }
        .background(Color(role: .bgCanvas, in: theme).ignoresSafeArea())
        .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: entry)
        .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: drafts)
        .haptic(.pick, trigger: style)
        .haptic(.appear, trigger: landed)
        .task {
            // Before the member types, 编一句 shows dice lines.
            drafts = DiceDisclaimerWriter.rollDefault(3)
            // Writing the reason comes first: the page opens with the keyboard up.
            isEditing = true
        }
    }

    private var title: Text {
        switch (day == nil, restDay) {
        case (true, false): Text(copy: "今日请假条", bundle: .module)
        case (false, false): Text(copy: "请假条", bundle: .module)
        case (true, true): Text(copy: "今日休息", bundle: .module)
        case (false, true): Text(copy: "休息", bundle: .module)
        }
    }

    /// The excuse to post, or nil while it can't be.
    private var disclaimer: Disclaimer? { entry.disclaimer(restDay: restDay) }

    private func post() {
        guard let disclaimer, !model.isSending, !(model.compose?.isPreparingPhotos ?? false) else { return }
        Task { await model.post(.disclaimer(disclaimer, photos: photos), shared: isShared, on: day) }
    }

    /// The photos picked for it, the cover first.
    private var photos: [PreparedPhoto] {
        (model.compose?.photos ?? []).compactMap { if case .new(let photo) = $0 { photo } else { nil } }
    }

    /// The excuse, on the ticket's face: room for its four lines from the start, so the ticket
    /// doesn't jump while typing; under it 用回我写的 once a line replaced the member's words, and
    /// the count.
    private var face: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            TextField(text: $text, axis: .vertical) {
                if restDay {
                    Text(copy: "今天怎么歇？", bundle: .module)
                } else {
                    Text(copy: "为什么没练？", bundle: .module)
                }
            }
            .typeStyle(TypeRamp.field)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .lineLimit(Self.lines, reservesSpace: true)
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
            HStack {
                if entry.canRestore {
                    Button {
                        entry.restore()
                        text = entry.text
                    } label: {
                        Label {
                            Text(copy: "用回我写的", bundle: .module)
                        } icon: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                    }
                    .accessibilityIdentifier("disclaimer.restore")
                }
                Spacer(minLength: Space.xs)
                Text(verbatim: "\(entry.text.count)/\(Disclaimer.maxLength)")
                    .typeStyle(TypeRamp.caption)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .monospacedDigit()
                    .accessibilityIdentifier("disclaimer.count")
            }
        }
    }

    /// The excuse's room on the ticket, in lines.
    private static let lines = 4

    /// Below the tear: 帮我编一句 over the styles and the button that puts a line up, then the
    /// photos with the W.
    private var stub: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionLabel(Text(copy: "帮我编一句", bundle: .module))
            choices
            if let compose = model.compose {
                PhotoTiles(model: compose)
                    .padding(.top, Space.xs)
            } else {
                HStack {
                    Spacer()
                    TicketStamp()
                }
            }
        }
    }

    /// The styles and the button that puts a line up, one height on one row where it fits, the
    /// styles taking the room the button leaves (else, at large text sizes, the button goes under
    /// the styles).
    private var choices: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.xs) {
                styles.frame(maxWidth: .infinity)
                write
            }
            VStack(alignment: .leading, spacing: Space.xxs) {
                styles
                write
            }
        }
    }

    /// The four styles as the system's segmented control, as tall as 编一句 beside it. Picking
    /// only picks: it asks nothing.
    private var styles: some View {
        Picker(selection: $style) {
            ForEach(DisclaimerStyle.allCases, id: \.self) { option in
                option.label.tag(option)
            }
        } label: {
            Text(copy: "风格", bundle: .module)
        }
        .pickerStyle(.segmented)
        .disabled(isWriting)
        .accessibilityIdentifier("disclaimer.style")
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
/// after; it is the only thing that asks the writer. A graphite secondary button, so it reads
/// before the style pills beside it.
private struct WriteButton: View {
    let isAgain: Bool
    let isWriting: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                if isAgain {
                    Text(copy: "换一句", bundle: .module)
                } else {
                    Text(copy: "编一句", bundle: .module)
                }
            } icon: {
                // While the writer works, 三拍 in the icon's place (loader design A).
                LoadingSwap(isWriting) {
                    Image(systemName: isAgain ? "arrow.clockwise" : "wand.and.sparkles")
                }
            }
        }
        .buttonStyle(SecondaryButtonStyle(size: .compact))
        .fixedSize()
        .disabled(isWriting)
        .accessibilityIdentifier("disclaimer.write")
    }
}

extension DisclaimerStyle {
    /// The style's tab label.
    var label: Text {
        switch self {
        case .funny: Text(copy: "搞笑", bundle: .module)
        case .unhinged: Text(copy: "发疯", bundle: .module)
        case .heroic: Text(copy: "中二", bundle: .module)
        case .stubborn: Text(copy: "嘴硬", bundle: .module)
        }
    }
}

#endif
