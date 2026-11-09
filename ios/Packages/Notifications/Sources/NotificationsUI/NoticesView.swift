#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import NotificationsDomain
import SwiftUI

/// The member's own character, standing on the empty 通知.
public struct NoticeViewer: Hashable, Sendable {
    public let outfit: Outfit
    public let persona: Persona

    public init(outfit: Outfit, persona: Persona) {
        (self.outfit, self.persona) = (outfit, persona)
    }
}

/// What a store or prop that opened says on its row: the editor's own names and badge
/// (`CharacterEditorUI`'s `UnlockNames`), which the app passes in.
public struct UnlockWords {
    public let title: Text
    public let detail: Text?
    public let icon: AnyView

    public init(title: Text, detail: Text?, icon: AnyView) {
        (self.title, self.detail, self.icon) = (title, detail, icon)
    }
}

/// 通知, opened from the bell on 动态 (the approved bell design): everything the member was told,
/// under 今天, 本周 and 更早, newest first (what was said on one post in a day is one row), the
/// ones that were new in bold with a dot. Opening it
/// marks them all read. A tap on a row goes where it points. Empty, the member's character
/// stands there with 还没有通知.
public struct NoticesView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let inbox: NoticeInbox
    private let viewer: NoticeViewer?
    private let unlocked: (Unlock.Kind, String) -> UnlockWords
    private let now: () -> Date
    private let open: (AppDestination) -> Void

    /// - Parameters:
    ///   - unlocked: a store's or prop's words and badge, by its id in the art.
    ///   - now: the time the rows' groups and times are told against.
    ///   - open: a row was tapped, for where it goes (`Notice.destination`); the page stays until
    ///     the caller pops it.
    public init(
        inbox: NoticeInbox, viewer: NoticeViewer?, unlocked: @escaping (Unlock.Kind, String) -> UnlockWords,
        now: @escaping () -> Date = Date.init, open: @escaping (AppDestination) -> Void
    ) {
        self.inbox = inbox
        self.viewer = viewer
        self.unlocked = unlocked
        self.now = now
        self.open = open
    }

    public var body: some View {
        ZStack {
            Color(role: .bgCanvas, in: .gym).ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.xs) {
                    Text(copy: "通知", bundle: .module)
                        .typeStyle(TypeRamp.largeTitle)
                        .foregroundStyle(Color(role: .fgDefault, in: .gym))
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, Space.xs)
                    content
                }
                .padding(.horizontal, Space.pageMargin)
                .padding(.top, Space.xs)
                .padding(.bottom, Space.l)
            }
            .barTitleOnScroll(Text(copy: "通知", bundle: .module))
            .refreshable { await inbox.refresh() }
        }
        .loadingCover(inbox.phase == .loading && inbox.notices.isEmpty) {
            TicketSpinner()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(role: .bgCanvas, in: .gym))
        }
        .pushedPage()
        // Opened once while the page is on the stack: a post pushed over it and back keeps what
        // was new and the pages read further down. The app closes the inbox when it pops the page.
        .task {
            guard !inbox.isOpen else { return }
            await inbox.open()
        }
        .accessibilityIdentifier("notices.page")
    }

    @ViewBuilder private var content: some View {
        if inbox.notices.isEmpty {
            // Pages of kinds this build can't show may hide older ones it can: read on to them.
            if inbox.hasMore {
                more
            } else if inbox.phase == .current {
                EmptyNotices(viewer: viewer)
            } else if inbox.phase == .offline {
                StateView.offline(retryIdentifier: "notices.retry") { Task { await inbox.open() } }
                    .padding(.top, Space.xxl)
            }
        } else {
            let shownAt = now()
            ForEach(NoticeSection.sections(inbox.notices, now: shownAt, calendar: .current)) { section in
                SectionLabel(section.heading.title)
                    .padding(.top, Space.s)
                ForEach(section.entries) { entry in
                    Button {
                        // The same place its banner and its push open.
                        if let destination = entry.notice.destination { open(destination) }
                    } label: {
                        NoticeRow(
                            entry: entry, heading: section.heading,
                            isUnread: entry.notices.contains(where: inbox.isUnread),
                            now: shownAt, unlocked: unlocked)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityIdentifier("notices.row.\(entry.id.rawValue)")
                }
            }
            if inbox.hasMore {
                more
            }
        }
    }

    /// The end of what is loaded: reads the next page as it comes into view, or offers to try
    /// again after a failed one.
    @ViewBuilder private var more: some View {
        Group {
            if inbox.moreFailed {
                // As 我的动态's wall: the page so far stays, with a way to read on.
                Button {
                    Task { await inbox.loadMore() }
                } label: {
                    Text(copy: "再试一次", bundle: .module)
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("notices.loadMore")
            } else {
                // Again after each page read, while the end is still in view, even one that had
                // nothing this build can show.
                LoadingDots()
                    .task(id: inbox.nextPage) { await inbox.loadMore() }
            }
        }
        .frame(maxWidth: .infinity, minHeight: Sizing.control)
    }
}

extension NoticeHeading {
    var title: Text {
        switch self {
        case .today: Text(copy: "今天", bundle: .module)
        case .thisWeek: Text(copy: "本周", bundle: .module)
        case .earlier: Text(copy: "更早", bundle: .module)
        }
    }
}

/// No notices yet: the member's own character standing in a circle, and one line.
private struct EmptyNotices: View {
    let viewer: NoticeViewer?
    @State private var player: CharacterPlayer?

    private static let circle: Double = 136

    var body: some View {
        VStack(spacing: Space.s) {
            ZStack(alignment: .bottom) {
                Circle().fill(Color(role: .bgBrand, in: .gym))
                if let player {
                    CharacterView(player: player)
                        .frame(height: Self.circle * 0.86)
                }
            }
            .frame(width: Self.circle, height: Self.circle)
            .clipShape(Circle())
            .accessibilityHidden(true)
            Text(copy: "还没有通知", bundle: .module)
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: .gym))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.xxl)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("notices.empty")
        .task(id: viewer) { player = Self.player(for: viewer) }
    }

    private static func player(for viewer: NoticeViewer?) -> CharacterPlayer? {
        let outfit = viewer?.outfit ?? PlaceholderCharacter.lifter
        guard let figure = try? PlaceholderCharacter.figure(wearing: outfit),
            let idle = try? PlaceholderCharacter.clip("idle", persona: viewer?.persona ?? .energetic)
        else { return nil }
        return try? CharacterPlayer(figure: figure, idle: idle)
    }
}
#endif
