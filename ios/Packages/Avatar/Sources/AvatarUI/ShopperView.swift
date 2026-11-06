#if canImport(SwiftUI)
import AvatarArt
import AvatarDomain
import SwiftUI

/// The member on 商店街, carrying the shopping bags: strolling in place while `walking` (the
/// street sliding to the next store), and, once it stops, spotting something good in the window
/// (`PlaceholderCharacter.shoppingSpot()`) and then idling as `persona`, the bags hanging still.
/// Always facing front, whichever way the street goes.
public struct ShopperView: View {
    private let look: Outfit
    private let persona: Persona
    private let walking: Bool
    @State private var shopper: Shopper?

    public init(look: Outfit, persona: Persona, walking: Bool) {
        self.look = look
        self.persona = persona
        self.walking = walking
    }

    public var body: some View {
        Group {
            if let shopper {
                CharacterView(player: shopper.player)
            } else {
                Color.clear.aspectRatio(240.0 / 320.0, contentMode: .fit)
            }
        }
        .accessibilityHidden(true)
        .task(id: Key(look: look, persona: persona)) {
            shopper = try? Shopper(look: look, persona: persona, walking: walking)
        }
        .onChange(of: walking) { _, walking in
            if walking { shopper?.walk() } else { shopper?.stop() }
        }
    }

    private struct Key: Equatable {
        let look: Outfit
        let persona: Persona
    }
}

/// The player and the clips it switches between, parsed once.
@MainActor
private struct Shopper {
    let player: CharacterPlayer
    let figure: Figure
    let walking: Clip
    let spot: Clip
    let idle: Clip

    init(look: Outfit, persona: Persona, walking isWalking: Bool) throws(AvatarError) {
        let shopper = PlaceholderCharacter.shopping(look)
        figure = try PlaceholderCharacter.figure(wearing: shopper)
        walking = try PlaceholderCharacter.shoppingWalk()
        spot = try PlaceholderCharacter.shoppingSpot()
        idle = try PlaceholderCharacter.clip(
            "idle", persona: persona, species: PlaceholderCharacter.species(of: shopper))
        player = try CharacterPlayer(figure: figure, idle: isWalking ? walking : idle)
    }

    func walk() {
        try? player.wear(figure, idle: walking)
    }

    func stop() {
        try? player.wear(figure, idle: idle)
        try? player.play(spot)
    }
}

#Preview("Shopper") {
    @Previewable @State var walking = true
    ShopperView(look: PlaceholderCharacter.lifter, persona: .energetic, walking: walking)
        .frame(height: 320)
        .onTapGesture { walking.toggle() }
}
#endif
