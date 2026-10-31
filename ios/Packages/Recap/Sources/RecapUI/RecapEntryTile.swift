#if os(iOS)
import AvatarDomain
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import RecapDomain
import SwiftUI

/// The 战报's way in from 动态 (揭开红布): the week's dates, 每周战报, and the podium. Until the
/// reader watches the story to the end it stays under its cloth with only them peeking, and a
/// 「新」 beside the dates, so opening it is the surprise; after, the cloth is off and the reader
/// stands on their own step, with 再看一遍. The tile takes that week's scene's colours.
public struct RecapEntryTile: View {
    private let story: WeekStory
    private let viewer: StoryMember?
    private let seen: Bool
    private let action: @MainActor () -> Void
    @State private var figure: (drawing: FigureDrawing, placements: [Placement])?

    /// - Parameters:
    ///   - viewer: the reader as the story keeps them, who peeks from behind the cloth, or
    ///     stands on their step once seen.
    ///   - seen: the reader watched this story to its last page.
    public init(story: WeekStory, viewer: StoryMember?, seen: Bool, action: @escaping @MainActor () -> Void) {
        self.story = story
        self.viewer = viewer
        self.seen = seen
        self.action = action
    }

    private var theme: SceneTheme { story.scene }

    public var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Space.xs) {
                        Text(verbatim: story.week.label)
                            .typeStyle(TypeRamp.scoreInline)
                        if !seen {
                            Text("新", bundle: .module)
                                .typeStyle(TypeRamp.label)
                                .foregroundStyle(Color(role: .fgOnAccent, in: theme))
                                .padding(.horizontal, Space.xs)
                                .frame(height: 20)
                                .background(Color(role: .bgAccent, in: theme), in: Capsule())
                        }
                    }
                    Text("每周战报", bundle: .module)
                        .typeStyle(TypeRamp.taskTitle)
                    Spacer(minLength: Space.s)
                    if seen {
                        Text("已看完 · 再看一遍", bundle: .module)
                            .typeStyle(TypeRamp.footnoteEmphasis)
                            .foregroundStyle(Color(role: .fgAccent, in: theme))
                    } else {
                        segments
                    }
                }
                .foregroundStyle(Color(role: seen ? .fgDefault : .fgOnScene, in: theme))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(Space.m)
                if seen { uncovered } else { covered }
            }
            .frame(height: Self.height)
            .background(
                Color(role: seen ? .bgAccentSubtle : .bgScene, in: theme),
                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .environment(\.sceneTheme, theme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            seen
                ? Text("每周战报，\(story.week.label)，已看完", bundle: .module)
                : Text("每周战报，\(story.week.label)，未读", bundle: .module)
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("recap.entry")
        .task(id: FigureKey(viewer: viewer, seen: seen)) {
            figure = viewer.flatMap { seen ? StoryWardrobe.standing($0) : StoryWardrobe.peeking($0) }
        }
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

    /// The podium uncovered, 2 1 3, the reader standing on their own step, or beside it when
    /// they weren't on it.
    private var uncovered: some View {
        let step = viewer.flatMap { story.podium?.step(of: $0.id) }
        let width = Self.podiumWidth + (step == nil ? Self.besideWidth : 0)
        return ZStack(alignment: .bottomLeading) {
            OpenPodium()
                .frame(width: Self.podiumWidth, height: Self.podiumHeight)
                .offset(x: width - Self.podiumWidth)
            if let figure {
                let feet = step.map { OpenPodium.top(of: $0) } ?? Self.podiumHeight
                let centre = step.map { width - Self.podiumWidth + OpenPodium.centre(of: $0) } ?? Self.besideWidth / 2
                CharacterCanvas(drawing: figure.drawing, placements: figure.placements)
                    .frame(width: 240 * Self.standScale, height: 320 * Self.standScale)
                    .offset(
                        x: centre - 120 * Self.standScale,
                        y: -(Self.podiumHeight - feet) + 320 * Self.standScale * (1 - Self.feet))
            }
        }
        .frame(width: width, height: Self.podiumHeight + Self.headroom, alignment: .bottomLeading)
        .padding(.trailing, Space.s)
    }

    private struct FigureKey: Hashable {
        let viewer: StoryMember?
        let seen: Bool
    }

    /// The design's tile: 343 by 168 on a 390-wide phone.
    private static let height: Double = 168
    private static let peekScale = 0.34
    private static let standScale = 0.26
    /// Where a character's feet are on its 240 by 320 canvas, from the top.
    private static let feet = 312.0 / 320
    private static let podiumWidth: Double = 130
    private static let podiumHeight: Double = 64
    private static let besideWidth: Double = 48
    /// Room above the top step for the one standing on it.
    private static let headroom: Double = 64
}

extension Podium {
    /// Where a member stands: 1 in the middle for the champion, then 2 on the left and 3 on the
    /// right; nil when they weren't on it.
    fileprivate func step(of member: MemberID) -> Int? {
        if member == champion { return 1 }
        return sides.firstIndex(of: member).map { $0 + 2 }
    }
}

/// The podium without its cloth: three white steps in the scene's accent, 2 1 3.
private struct OpenPodium: View {
    @Environment(\.sceneTheme) private var theme

    /// Each step's left edge, width and height on the 130 by 64 podium, by its number.
    private static let steps: [Int: (left: Double, width: Double, height: Double)] = [
        2: (0, 40, 40), 1: (44, 42, 64), 3: (90, 40, 30),
    ]

    static func centre(of step: Int) -> Double {
        steps[step].map { $0.left + $0.width / 2 } ?? 0
    }

    /// How far down from the podium's top the step's top is.
    static func top(of step: Int) -> Double {
        steps[step].map { 64 - $0.height } ?? 64
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ForEach([2, 1, 3], id: \.self) { number in
                if let step = Self.steps[number] {
                    Text(verbatim: "\(number)")
                        .typeStyle(TypeRamp.scoreSmall)
                        .foregroundStyle(Color(role: .fgAccent, in: theme))
                        .frame(width: step.width, height: step.height)
                        .background(Color(role: .bgCanvas, in: theme))
                        .overlay(Rectangle().strokeBorder(Color(role: .bgAccent, in: theme), lineWidth: 2))
                        .offset(x: step.left)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .accessibilityHidden(true)
    }
}
#endif
