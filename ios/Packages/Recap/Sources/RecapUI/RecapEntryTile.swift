#if os(iOS)
import AvatarDomain
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import RecapDomain
import SwiftUI

/// The 战报's way in from 动态: the week, 本周战报, and the podium under its cloth with only you
/// peeking. It shows no award, winner or number, so opening the story is the surprise.
public struct RecapEntryTile: View {
    private let week: Week
    private let pages: Int
    private let viewer: StoryMember?
    private let action: @MainActor () -> Void
    @Environment(\.sceneTheme) private var theme
    @State private var peek: (drawing: FigureDrawing, placements: [Placement])?

    /// - Parameters:
    ///   - pages: how many pages the story has, for the segment ticks; never what is on them.
    ///   - viewer: the reader, who peeks from behind the cloth.
    public init(week: Week, pages: Int, viewer: StoryMember?, action: @escaping @MainActor () -> Void) {
        self.week = week
        self.pages = pages
        self.viewer = viewer
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: week.label)
                        .typeStyle(TypeRamp.label)
                    Text("本周战报", bundle: .module)
                        .typeStyle(TypeRamp.title)
                    Spacer(minLength: Space.s)
                    HStack(spacing: Space.xxs) {
                        ForEach(0..<max(pages, 1), id: \.self) { index in
                            Capsule()
                                .fill(Color(role: .fgOnScene, in: theme).opacity(index == 0 ? 1 : 0.15))
                                .frame(width: 18, height: 3)
                        }
                    }
                }
                .foregroundStyle(Color(role: .fgOnScene, in: theme))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(Space.m)
                ZStack(alignment: .bottomLeading) {
                    CoveredPodium().frame(width: 140)
                    if let peek {
                        CharacterCanvas(drawing: peek.drawing, placements: peek.placements)
                            .frame(width: 240 * Self.peekScale, height: 320 * Self.peekScale)
                            .offset(x: Space.xs, y: 320 * Self.peekScale * (1 - 312.0 / 320) + 2)
                    }
                }
                .padding(.trailing, Space.s)
            }
            .frame(height: Self.height)
            .background(
                Color(role: .bgScene, in: theme), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("本周战报，\(week.label)", bundle: .module))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("recap.entry")
        .task(id: viewer) { peek = viewer.flatMap(StoryWardrobe.peeking) }
    }

    /// The design's tile: 343 by 168 on a 390-wide phone.
    private static let height: Double = 168
    private static let peekScale = 0.34
}
#endif
