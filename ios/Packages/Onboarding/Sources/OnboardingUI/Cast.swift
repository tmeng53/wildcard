#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import Contracts
import DesignSystem
import Foundation
import Observation

/// One character on a sign-up screen: its player, built off the main actor since reading the
/// art takes a moment, and the clips it plays. Nil player until the first build is done.
@MainActor @Observable
final class CastMember {
    private(set) var player: CharacterPlayer?
    /// The character's own look, as saved.
    let look: Outfit
    let persona: Persona
    /// What it wears now: its look, or a sport's kit over it.
    @ObservationIgnored private(set) var outfit: Outfit
    /// False while it stands still beside a title, until a sport's move starts.
    @ObservationIgnored private var playsIdle = true
    @ObservationIgnored private var request = 0

    init(outfit: Outfit, persona: Persona) {
        look = outfit
        self.outfit = outfit
        self.persona = persona
    }

    /// Builds the figure and starts it on its idle. `idle: false` keeps it still until asked.
    func load(idle: Bool = true) async {
        playsIdle = idle
        guard player == nil, let figure = try? await Self.figure(wearing: outfit) else { return }
        player = try? CharacterPlayer(figure: figure, idle: idle ? self.idle : .still)
    }

    /// Puts on the kit of `activity` and plays its move, or, for nil, changes back into the
    /// character's own look.
    func dress(for activity: Activity?) {
        guard let activity, let kits = Self.kits else {
            change(into: look, move: nil)
            return
        }
        let kit = kits.kit(for: activity)
        change(into: kit.dress(look), move: try? PlaceholderCharacter.move(for: kit, persona: persona))
    }

    /// Puts on the kit of `scene`'s sport and loops its move, as on the scene itself.
    func train(on scene: SceneTheme) {
        guard let loop = try? PlaceholderCharacter.sceneLoop(for: scene, look: look, persona: persona) else { return }
        change(into: loop.outfit, move: loop.clip)
    }

    /// Changes into another outfit with a hop, then plays `move` in it, as a sport
    /// is picked. A newer change wins over a slower build.
    func change(into outfit: Outfit, move: Clip?) {
        request += 1
        let ticket = request
        self.outfit = outfit
        Task {
            guard let figure = try? await Self.figure(wearing: outfit), ticket == request, let player else { return }
            let idle = move ?? (self.playsIdle ? self.idle : .still)
            if let hop = try? PlaceholderCharacter.kitHop() {
                try? player.change(into: figure, idle: idle, hop: hop)
            } else {
                try? player.wear(figure, idle: idle)
            }
        }
    }

    /// Plays the persona's `name` clip once (`cheer`, `welcome`) from now.
    func play(_ name: String, now: Date = .now) {
        guard let player, let clip = clip(name) else { return }
        try? player.play(clip, now: now)
    }

    /// `blending: false` starts the clip at its own first frame, as the entrance must.
    func play(_ clip: Clip, now: Date = .now, blending: Bool = true) {
        try? player?.play(clip, now: now, blending: blending)
    }

    private var idle: Clip { clip("idle") ?? .still }

    /// The persona's clip with the moves of the outfit's species on top.
    private func clip(_ name: String) -> Clip? {
        try? PlaceholderCharacter.clip(name, persona: persona, species: PlaceholderCharacter.species(of: outfit))
    }

    private static let kits = try? PlaceholderCharacter.sportKits()

    /// Reads and parses the art for an outfit away from the main actor.
    nonisolated static func figure(wearing outfit: Outfit) async throws -> Figure {
        try await Task.detached(priority: .userInitiated) {
            try PlaceholderCharacter.figure(wearing: outfit)
        }.value
    }
}
#endif
