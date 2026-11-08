#if os(iOS)
import AvatarDomain
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import RecapDomain
import SwiftUI

/// The 战报's way in from 动态 (揭开红布): the week's dates with 「新」, 每周战报, and the podium
/// under its cloth with the reader peeking, so opening it is the surprise. 动态 shows it only
/// until the reader watches the story to the end; after, the story is on 小队's 往期战报. The
/// tile takes that week's scene's colours.
public struct RecapEntryTile: View {
    private let story: WeekStory
    private let viewer: StoryMember?
    private let action: @MainActor () -> Void
    @State private var figure: (drawing: FigureDrawing, placements: [Placement])?

    /// - Parameters:
    ///   - viewer: the reader as the story keeps them, who peeks from behind the cloth.
    public init(story: WeekStory, viewer: StoryMember?, action: @escaping @MainActor () -> Void) {
        self.story = story
        self.viewer = viewer
        self.action = action
    }

    private var theme: SceneTheme { story.scene }

    public var body: some View {
        Button(action: action) { tile }
            .buttonStyle(PressableButtonStyle())
            .environment(\.sceneTheme, theme)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("每周战报，\(story.week.label)，未读", bundle: .module))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("recap.entry")
            .task(id: viewer) { figure = viewer.flatMap(StoryWardrobe.peeking) }
    }

    /// The dates with 「新」, 每周战报, its pages as ticks and the podium under its cloth.
    private var tile: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Space.xs) {
                    Text(verbatim: story.week.label)
                        .typeStyle(TypeRamp.scoreInline)
                    Text("新", bundle: .module)
                        .typeStyle(TypeRamp.label)
                        .foregroundStyle(Color(role: .fgOnAccent, in: theme))
                        .padding(.horizontal, Space.xs)
                        .frame(height: 20)
                        .background(Color(role: .bgAccent, in: theme), in: Capsule())
                }
                Text("每周战报", bundle: .module)
                    .typeStyle(TypeRamp.taskTitle)
                Spacer(minLength: Space.s)
                segments
            }
            .foregroundStyle(Color(role: .fgOnScene, in: theme))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Space.m)
            covered
        }
        .frame(height: Self.height)
        .background(
            Color(role: .bgScene, in: theme), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    /// How many pages the story has, as ticks; never what is on them.
    private var segments: some View {
        HStack(spacing: Space.xxs) {
            ForEach(0..<max(story.pages.count, 1), id: \.self) { index in
                Capsule()
                    .fill(Color(role: .fgOnScene, in: theme).opacity(index == 0 ? 1 : 0.15))
                    .frame(width: 18, height: 3)
            }
        }
    }

    /// The podium under its cloth, the reader leaning out from behind it.
    private var covered: some View {
        ZStack(alignment: .bottomLeading) {
            CoveredPodium().frame(width: 140)
            if let figure {
                CharacterCanvas(drawing: figure.drawing, placements: figure.placements)
                    .frame(width: 240 * Self.peekScale, height: 320 * Self.peekScale)
                    .offset(x: Space.xs, y: 320 * Self.peekScale * (1 - Self.feet) + 2)
            }
        }
        .padding(.trailing, Space.s)
    }

    /// The design's tile: 343 by 168 on a 390-wide phone.
    private static let height: Double = 168
    private static let peekScale = 0.34
    /// Where a character's feet are on its 240 by 320 canvas, from the top.
    private static let feet = 312.0 / 320
}
#endif
