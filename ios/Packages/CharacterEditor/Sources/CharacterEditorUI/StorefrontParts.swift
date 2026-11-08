#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import DesignSystem
import DesignSystemUI
import SwiftUI

// The parts of a store's front on 商店街 (`StoreStreet`'s `Storefront`) that are the store's own:
// its sign and the model in its window. The painted parts (awning, glass, door, shutter, street)
// are DesignSystemUI's `Shop…` views.

/// The sign over the awning: the store's colour, its badge on a white disc and its name, and a
/// limited store's tag at the end. A closed store's sign is grey and says 「? ? ?」.
struct StoreSign: View {
    let store: EditorChoices.Store
    @Environment(\.sceneTheme) private var theme
    private let badge: Double = 32

    var body: some View {
        HStack(spacing: Space.xs) {
            if store.isOpen {
                StoreBadge(store: store.id)
                    .padding(Space.xs - Space.xxs / 2)
                    .frame(width: badge, height: badge)
                    .background(Color(role: .bgCanvas, in: theme), in: Circle())
                StoreCopy.name(store.id)
                    .typeStyle(TypeRamp.scoreCard)
                    .foregroundStyle(StoreLook.signInk(store.id, in: theme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Spacer(minLength: 0)
                if let tag = LimitedTag(store: store.id) {
                    tag.background(
                        Color(role: .bgCanvas, in: theme),
                        in: RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous))
                }
            } else {
                Text(verbatim: "? ? ?")
                    .typeStyle(TypeRamp.scoreCard)
                    .foregroundStyle(Color(role: .fgOnBrand, in: theme))
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Space.xs + Space.xxs / 2)
        .frame(height: Sizing.control)
        .background(
            store.isOpen ? StoreLook.color(store.id, in: theme) : Color(role: .fgMuted, in: theme),
            in: RoundedRectangle(cornerRadius: Radius.pick, style: .continuous))
    }
}

/// The model in a store's window: a character in the store's clothes (`stores/<id>.json`),
/// idling on a plinth in a tint of the store's colour. Built off the main actor, so the street
/// doesn't drop a frame as it opens; a store without a model shows the empty plinth.
struct WindowModel: View {
    let store: String
    let color: Color
    @State private var player: CharacterPlayer?
    private let plinth = CGSize(width: 104, height: 20)

    var body: some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(color.opacity(0.45))
                .overlay(alignment: .bottom) {
                    Ellipse().fill(color.opacity(0.25)).frame(height: plinth.height * 0.7)
                }
                .frame(width: plinth.width, height: plinth.height)
            if let player {
                CharacterView(player: player)
                    .padding(.bottom, plinth.height / 2 - Space.xxs)
            }
        }
        .accessibilityHidden(true)
        .task(id: store) {
            let store = store
            guard
                let model = try? await Task.detached(operation: { try ModelFigure(store: store) }).value,
                !Task.isCancelled
            else { return }
            player = try? CharacterPlayer(figure: model.figure, idle: model.idle)
        }
    }
}

/// A window model's figure and idle, parsed once.
private struct ModelFigure: Sendable {
    let figure: Figure
    let idle: Clip

    init(store: String) throws(AvatarError) {
        guard let window = PlaceholderCharacter.storeWindow(store) else { throw .missingFile("stores/\(store).json") }
        let outfit = try PlaceholderCharacter.drawable(window.outfit)
        figure = try PlaceholderCharacter.figure(wearing: outfit)
        idle = try PlaceholderCharacter.clip(
            "idle", persona: window.persona, species: PlaceholderCharacter.species(of: outfit))
    }
}
#endif
