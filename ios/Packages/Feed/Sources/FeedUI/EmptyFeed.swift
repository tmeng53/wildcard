#if os(iOS)
import AvatarArt
import AvatarUI
import CheckInUI
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// No posts yet: a window onto the squad's own scene, with my character there in the scene's kit
/// doing its sport, then 今天还没人上场 and 去打卡 (the approved empty feed).
struct EmptyFeed: View {
    @Environment(\.sceneTheme) private var theme
    let model: FeedModel
    let checkIn: () -> Void
    @State private var player: CharacterPlayer?

    /// The part of the 390 by 844 scene the window shows, in the scene's points: the venue and
    /// the floor in front of it.
    private static let window = (top: 250.0, height: 300.0)
    /// Where my character's feet are in the scene's points.
    private static let feet = 520.0
    /// The scene's art size, in points.
    private static let scene = CGSize(width: 390, height: 844)

    var body: some View {
        VStack(spacing: Space.l) {
            GeometryReader { proxy in
                let scale = proxy.size.width / Self.scene.width
                ZStack(alignment: .topLeading) {
                    SceneArt(scene: theme, layer: .day)
                        .frame(width: proxy.size.width, height: Self.scene.height * scale)
                        .offset(y: -Self.window.top * scale)
                    if let player {
                        CharacterView(player: player)
                            .frame(height: Sizing.characterFull)
                            .frame(maxWidth: .infinity)
                            .offset(y: (Self.feet - Self.window.top) * scale - Sizing.characterFull)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
            .aspectRatio(Self.scene.width / Self.window.height, contentMode: .fit)
            .accessibilityHidden(true)

            Text("今天还没人上场", bundle: .module)
                .typeStyle(TypeRamp.headline)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
            Button(action: checkIn) {
                Label {
                    Text("去打卡", bundle: .module)
                } icon: {
                    Image(systemName: "plus")
                        .font(.system(size: Sizing.smallIcon, weight: .bold))
                }
            }
            .buttonStyle(PrimaryButtonStyle(.regular))
            .accessibilityIdentifier("feed.checkIn")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.xs)
        .task { player = makePlayer() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feed.empty")
    }

    /// Me in the scene's kit, doing its sport on a loop.
    private func makePlayer() -> CharacterPlayer? {
        let look = model.store.characters[model.viewer]?.look
        let persona = look?.moves ?? .energetic
        guard let kits = try? PlaceholderCharacter.sportKits() else { return nil }
        let kit = kits.kit(for: .sport(theme.sport))
        guard
            let figure = try? PlaceholderCharacter.figure(
                wearing: kit.dress(look?.outfit ?? PlaceholderCharacter.lifter)),
            let move = try? PlaceholderCharacter.move(for: kit, persona: persona)
        else { return nil }
        return try? CharacterPlayer(figure: figure, idle: move)
    }
}

extension SceneTheme {
    /// The sport the scene is for.
    var sport: Sport {
        switch self {
        case .pool: .swim
        case .track: .run
        case .gym: .strength
        case .tennis: .tennis
        case .climbing: .climb
        }
    }
}
#endif
