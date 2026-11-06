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
            // Parsed off the main actor, so the street doesn't drop a frame as it opens.
            let (look, persona) = (look, persona)
            guard
                let moves = try? await Task.detached(operation: { try ShopperMoves(look: look, persona: persona) })
                    .value
            else { return }
            // A newer look's task replaced this one while it parsed.
            guard !Task.isCancelled else { return }
            shopper = try? Shopper(moves, walking: walking)
        }
        .task(id: walking) {
            guard let shopper else { return }
            if walking {
                shopper.walk()
            } else {
                // The spot starts from the walk's first frame: let the step under way finish.
                try? await Task.sleep(for: .seconds(shopper.restOfStep()))
                if !Task.isCancelled { shopper.stop() }
            }
        }
    }

    private struct Key: Equatable {
        let look: Outfit
        let persona: Persona
    }
}

/// The shopper's figure and clips, parsed once.
private struct ShopperMoves: Sendable {
    let figure: Figure
    let walking: Clip
    let spot: Clip
    let idle: Clip

    init(look: Outfit, persona: Persona) throws(AvatarError) {
        let shopper = PlaceholderCharacter.shopping(look)
        figure = try PlaceholderCharacter.figure(wearing: shopper)
        walking = try PlaceholderCharacter.shoppingWalk()
        spot = try PlaceholderCharacter.shoppingSpot()
        idle = try PlaceholderCharacter.clip(
            "idle", persona: persona, species: PlaceholderCharacter.species(of: shopper))
    }
}

/// The player and when its walk began.
@MainActor
private final class Shopper {
    let player: CharacterPlayer
    private let moves: ShopperMoves
    private var walkingSince: Date?

    init(_ moves: ShopperMoves, walking: Bool, now: Date = .now) throws(AvatarError) {
        self.moves = moves
        player = try CharacterPlayer(figure: moves.figure, idle: walking ? moves.walking : moves.idle, now: now)
        walkingSince = walking ? now : nil
    }

    func walk(now: Date = .now) {
        guard walkingSince == nil else { return }
        try? player.wear(moves.figure, idle: moves.walking, now: now)
        walkingSince = now
    }

    /// Seconds until the walk is back at its first frame; none when not walking.
    func restOfStep(now: Date = .now) -> Double {
        guard let since = walkingSince else { return 0 }
        let into = now.timeIntervalSince(since).truncatingRemainder(dividingBy: moves.walking.duration)
        return into < 0.02 ? 0 : moves.walking.duration - into
    }

    func stop(now: Date = .now) {
        guard walkingSince != nil else { return }
        walkingSince = nil
        try? player.wear(moves.figure, idle: moves.idle, now: now)
        try? player.play(moves.spot, now: now)
    }
}

#Preview("Shopper") {
    @Previewable @State var walking = true
    ShopperView(look: PlaceholderCharacter.lifter, persona: .energetic, walking: walking)
        .frame(height: 320)
        .onTapGesture { walking.toggle() }
}
#endif
