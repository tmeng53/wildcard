#if os(iOS)
import AvatarUI
import ChatDomain
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// 群聊 (approved 2026-11-04): the squad's chat under a glass header (返回, the squad's name over
/// its heads, the bell) with the glass composer floating at the bottom, the messages scrolling
/// under both as in iOS 26's Messages. The coach answers when someone @s it or replies to it, its
/// three dots first; its 战术板 line comes each morning as its card.
public struct ChatView: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Bindable private var model: ChatModel
    private let close: () -> Void
    @State private var listening: Task<Void, Never>?

    /// Messages further apart than this get the time between them.
    private static let timeGap: TimeInterval = 10 * 60
    /// Messages by the same writer this close together share a head and name.
    private static let runGap: TimeInterval = 3 * 60

    public init(model: ChatModel, close: @escaping () -> Void) {
        self.model = model
        self.close = close
    }

    public var body: some View {
        ZStack {
            Color(role: .bgCanvas, in: theme).ignoresSafeArea()
            transcript
                .blur(radius: model.lifted == nil ? 0 : Space.xs)
                .safeAreaInset(edge: .top, spacing: 0) { header }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ComposerBar(model: model).padding(.horizontal, Space.xs + 2).padding(.bottom, Space.xs)
                }
            if model.store.phase == .offline {
                VStack {
                    Text("网络开小差了", bundle: .module)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgOnBrand, in: theme))
                        .padding(.horizontal, Space.s + 2)
                        .padding(.vertical, Space.xs - 2)
                        .background(Color(role: .bgBrand, in: theme), in: Capsule())
                        .padding(.top, Space.xxl + Space.xl + Space.xs)
                        .accessibilityIdentifier("chat.offline")
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
            }
            if let lifted = model.lifted, let line = model.store.lines.first(where: { $0.id == lifted }) {
                LiftedMessage(model: model, line: line)
                    .transition(.opacity)
            }
            if let id = model.whoReacted, let message = model.store.message(id) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { model.whoReacted = nil }
                    .accessibilityHidden(true)
                WhoReacted(model: model, message: message)
                    .padding(Space.m)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: model.store.phase)
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: model.lifted)
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: model.whoReacted)
        .noticeBanner(item: $model.reportedNotice) { _ in
            NoticeBanner(Text("已举报，我们会看一下", bundle: .module)) {
                Image(systemName: "flag.fill")
                    .foregroundStyle(Color(role: .fgOnBrand, in: theme))
            }
        }
        .task {
            await model.store.load()
            listen()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { listen() } else { listening?.cancel() }
        }
        .onDisappear { listening?.cancel() }
        .swipesBack(perform: close)
    }

    /// Hears live events while the chat is open, reconnecting when the stream drops.
    private func listen() {
        listening?.cancel()
        let store = model.store
        listening = Task {
            var pause: Duration = .seconds(1)
            while !Task.isCancelled {
                await store.listen()
                try? await Task.sleep(for: pause)
                pause = min(pause * 2, .seconds(30))
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Space.xs) {
            HeaderButton(Text("返回", bundle: .module), systemImage: "chevron.left", action: close)
                .accessibilityIdentifier("chat.back")
            VStack(spacing: Space.xxs) {
                Text(verbatim: model.squadName)
                    .typeStyle(TypeRamp.headline)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .lineLimit(1)
                HStack(spacing: Space.xxs / 2) {
                    ForEach(model.lineup.prefix(8), id: \.self) { author in
                        MemberHead(
                            player: model.head(of: author), size: Sizing.smallTag,
                            rim: author.isCoach ? .coach : .mist)
                    }
                }
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            AlertsMenu(model: model)
        }
        .padding(.horizontal, Space.s)
        .padding(.bottom, Space.xs)
        .background {
            Rectangle().fill(.clear).glassEffect(.regular, in: Rectangle()).ignoresSafeArea(edges: .top)
        }
    }

    // MARK: Transcript

    @ViewBuilder private var transcript: some View {
        if model.store.phase == .loading && model.store.lines.isEmpty {
            LoadingDots().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.store.phase == .notInSquad {
            StateView(Text("你已经不在这个小队了", bundle: .module))
        } else if model.store.isEmpty && model.store.coachTyping == nil {
            EmptyChat(model: model)
        } else {
            messages
        }
    }

    private var messages: some View {
        let lines = model.store.lines
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Space.xs + 2) {
                    if model.store.hasEarlier {
                        LoadingDots()
                            .frame(height: Sizing.control)
                            .task { await model.store.loadEarlier() }
                    }
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        let previous = index > 0 ? lines[index - 1].message : nil
                        if previous.map({ line.message.sentAt.timeIntervalSince($0.sentAt) > Self.timeGap }) ?? true {
                            TimeLabel(moment: line.message.sentAt)
                        }
                        if line.message.kind == .note {
                            NoteCard(model: model, line: line).id(line.id)
                        } else {
                            MessageRow(model: model, line: line, continues: continues(line.message, after: previous))
                                .id(line.id)
                        }
                    }
                    if let coach = model.store.coachTyping {
                        TypingRow(model: model, coach: coach).id("typing")
                    }
                }
                .padding(.horizontal, Space.s + 2)
                .padding(.vertical, Space.s)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: lines.last?.id) { _, last in
                guard let last else { return }
                withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) {
                    proxy.scrollTo(last, anchor: .bottom)
                }
                Task { await model.store.markRead() }
            }
            .onChange(of: model.store.coachTyping) { _, typing in
                guard typing != nil else { return }
                withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) {
                    proxy.scrollTo("typing", anchor: .bottom)
                }
            }
            .task { await model.store.markRead() }
        }
    }

    private func continues(_ message: ChatMessage, after previous: ChatMessage?) -> Bool {
        guard let previous, previous.kind == .text, previous.author == message.author else { return false }
        return message.sentAt.timeIntervalSince(previous.sentAt) < Self.runGap
    }
}

extension ChatAuthor {
    var isCoach: Bool {
        if case .coach = self { true } else { false }
    }
}

/// When the messages under it were sent: 今天 19:02, 昨天 22:40, or the date.
struct TimeLabel: View {
    @Environment(\.sceneTheme) private var theme
    let moment: Date

    var body: some View {
        let time = moment.formatted(.dateTime.hour().minute())
        return Group {
            if Calendar.current.isDateInToday(moment) {
                Text("今天 \(time)", bundle: .module)
            } else if Calendar.current.isDateInYesterday(moment) {
                Text("昨天 \(time)", bundle: .module)
            } else {
                Text(moment, format: .dateTime.month().day().hour().minute())
            }
        }
        .typeStyle(TypeRamp.caption)
        .foregroundStyle(Color(role: .fgSubtle, in: theme))
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xxs)
    }
}

/// Nothing said yet: the squad and the coach in a row, and 「场边还很安静」. The coach never
/// opens; the next morning's 战术板 is the first message.
struct EmptyChat: View {
    @Environment(\.sceneTheme) private var theme
    let model: ChatModel

    var body: some View {
        VStack(spacing: Space.s) {
            HStack(spacing: Space.s - 2) {
                ForEach(model.lineup, id: \.self) { author in
                    MemberHead(
                        player: model.head(of: author), size: Sizing.control, rim: author.isCoach ? .coach : .mist)
                }
            }
            Text("场边还很安静", bundle: .module)
                .typeStyle(TypeRamp.body)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("chat.empty")
    }
}

/// The bell: the glass menu of when this squad's messages are pushed, the chosen one ticked.
/// 不提醒 slashes the bell.
struct AlertsMenu: View {
    let model: ChatModel

    var body: some View {
        let alerts = model.store.alerts
        HeaderMenu(
            Text("消息提醒", bundle: .module), systemImage: alerts == .none ? "bell.slash" : "bell",
            items: [
                item(.mentions, Text("有人@我", bundle: .module), systemImage: "at"),
                item(.all, Text("每条消息", bundle: .module), systemImage: "bell"),
                item(.none, Text("不提醒", bundle: .module), systemImage: "bell.slash"),
            ]
        )
        .accessibilityIdentifier("chat.alerts")
    }

    private func item(_ choice: ChatAlerts, _ title: Text, systemImage: String) -> GlassMenuItem {
        GlassMenuItem(
            title, systemImage: systemImage, isSelected: model.store.alerts == choice,
            id: "chat.alerts.\(choice.rawValue)"
        ) {
            Task { await model.store.setAlerts(choice) }
        }
    }
}
#endif
