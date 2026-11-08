#if os(iOS)
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import RecapDomain
import SwiftUI

/// 往期战报 on 小队 (Tracy, 2026-11-08): every 战报 the squad has, as story covers in a row, the
/// latest first, scrolled sideways past the page's edge. Each cover takes its week's scene
/// colours and shows the week, the podium's heads all one size, the champion's title and name
/// and the squad's days against its plans; one the reader hasn't watched to the end wears a
/// ring and 「新」. A tap plays that week's story. Nothing shows for a squad without one yet. The
/// page it is on reads them (`RecapShelf.refreshPast`).
public struct PastRecaps: View {
    private let shelf: RecapShelf

    public init(shelf: RecapShelf) {
        self.shelf = shelf
    }

    public var body: some View {
        if !shelf.past.isEmpty {
            VStack(alignment: .leading, spacing: Space.labelGap) {
                HStack {
                    SectionLabel(Text("往期战报", bundle: .module))
                    Spacer(minLength: Space.xs)
                    SectionLabel(Text("\(shelf.past.count) 期", bundle: .module))
                }
                ScrollView(.horizontal) {
                    LazyHStack(spacing: Space.xs) {
                        ForEach(shelf.past, id: \.week.monday) { story in
                            RecapCover(story: story, viewer: shelf.reader, isNew: !shelf.isSeen(story)) {
                                Task { await shelf.open(story) }
                            }
                        }
                    }
                    // Room for the ring around a new cover.
                    .padding(.vertical, RecapCover.ringRoom)
                }
                .scrollIndicators(.hidden)
                // The row runs to the screen's edges while its first cover lines up with the page.
                .contentMargins(.horizontal, Space.pageMargin, for: .scrollContent)
                .padding(.horizontal, -Space.pageMargin)
                .padding(.vertical, -RecapCover.ringRoom)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("squad.pastRecaps")
        }
    }
}

/// One week's cover on 往期战报.
struct RecapCover: View {
    private let story: WeekStory
    private let viewer: MemberID?
    private let isNew: Bool
    private let action: @MainActor () -> Void
    @State private var heads: [CharacterPlayer?] = []

    init(story: WeekStory, viewer: MemberID?, isNew: Bool, action: @escaping @MainActor () -> Void) {
        self.story = story
        self.viewer = viewer
        self.isNew = isNew
        self.action = action
    }

    private var theme: SceneTheme { story.scene }

    var body: some View {
        Button(action: action) { cover }
            .buttonStyle(PressableButtonStyle())
            .environment(\.sceneTheme, theme)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(isNew ? Text("未读", bundle: .module) : Text(verbatim: ""))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("squad.pastRecap")
            .task(id: story.week.monday) { heads = podium.map { cast?.player(of: $0) } }
    }

    private var cover: some View {
        VStack(alignment: .leading, spacing: 0) {
            ticks
            HStack(alignment: .top, spacing: Space.xxs) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "\(story.week.monday.month).\(story.week.monday.day)")
                    Text(verbatim: "– \(story.week.sunday.month).\(story.week.sunday.day)")
                }
                .typeStyle(TypeRamp.scoreCaption)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                Spacer(minLength: 0)
                if isNew {
                    Text("新", bundle: .module)
                        .typeStyle(TypeRamp.label)
                        .foregroundStyle(Color(role: .fgOnAccent, in: theme))
                        .padding(.horizontal, Space.xxs)
                        .background(Color(role: .bgAccent, in: theme), in: Capsule())
                }
            }
            .padding(.top, Space.xs)
            Spacer(minLength: Space.xs)
            if !heads.isEmpty {
                HeadStack(heads, size: Self.head, on: .bgScene, limit: 3)
                    .padding(.bottom, Space.xs)
            }
            champion
            if let ending = story.ending, ending.plan > 0 {
                HStack(spacing: Space.xxs / 2) {
                    if ending.done >= ending.plan {
                        Image(systemName: "checkmark.circle.fill").accessibilityHidden(true)
                    }
                    Text("全队 \(ending.done)/\(ending.plan) 天", bundle: .module)
                }
                .typeStyle(TypeRamp.caption)
                .foregroundStyle(Color(role: .fgAccent, in: theme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, Space.xxs / 2)
            }
        }
        .padding(Space.xs)
        .frame(width: Self.width, height: Self.height, alignment: .topLeading)
        .background(
            Color(role: .bgScene, in: theme), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
        .overlay {
            if isNew {
                RoundedRectangle(cornerRadius: Radius.card + Self.ringRoom, style: .continuous)
                    .strokeBorder(Color(role: .bgAccent, in: theme), lineWidth: Sizing.selectionStroke)
                    .padding(-Self.ringRoom)
            }
        }
    }

    /// The champion's title with the crown, and their name under it.
    @ViewBuilder private var champion: some View {
        if let podium = story.podium {
            VStack(alignment: .leading, spacing: 0) {
                if let title = story.firstTitle(of: podium.champion) {
                    HStack(spacing: Space.xxs / 2) {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(Color(role: .fgAccent, in: theme))
                            .accessibilityHidden(true)
                        Text(verbatim: title)
                    }
                    .typeStyle(TypeRamp.footnoteEmphasis)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                }
                Text(verbatim: cast?.nickname(of: podium.champion) ?? "")
                    .typeStyle(TypeRamp.caption)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }

    /// How many pages the story has, as ticks, as on 动态's tile.
    private var ticks: some View {
        HStack(spacing: Space.xxs / 2) {
            ForEach(0..<max(story.pages.count, 1), id: \.self) { _ in
                Capsule()
                    .fill(Color(role: isNew ? .bgAccent : .fgMuted, in: theme).opacity(isNew ? 1 : 0.3))
                    .frame(height: 3)
            }
        }
    }

    private var cast: StoryCast? { viewer.map { StoryCast(story: story, viewer: $0) } }

    /// The podium left to right as it stands: the second, the champion, the third.
    private var podium: [MemberID] {
        guard let podium = story.podium else { return [] }
        return Array(podium.sides.prefix(1)) + [podium.champion] + Array(podium.sides.dropFirst())
    }

    private var accessibilityLabel: Text {
        let week = story.week.label
        guard let podium = story.podium, let name = cast?.nickname(of: podium.champion), !name.isEmpty else {
            return Text("每周战报，\(week)", bundle: .module)
        }
        return Text("每周战报，\(week)，冠军 \(name)", bundle: .module)
    }

    static let width: Double = 104
    static let height: Double = 164
    static let head: Double = 28
    /// How far a new cover's ring sits outside it.
    static let ringRoom: Double = 3
}
#endif
