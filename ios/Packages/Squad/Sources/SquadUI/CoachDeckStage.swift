#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import CheckInUI
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// A member as the coach page draws them: their look and persona.
public struct DeckCharacter: Hashable, Sendable {
    public let look: Outfit
    public let persona: Persona

    public init(look: Outfit, persona: Persona) {
        (self.look, self.persona) = (look, persona)
    }
}

/// Who stands on a card's stage: the member, and the squad for a line to everyone.
public struct DeckCast: Hashable, Sendable {
    public let member: DeckCharacter
    /// Everyone else in the squad, in the order they joined.
    public let mates: [DeckCharacter]
    public init(member: DeckCharacter, mates: [DeckCharacter]) {
        (self.member, self.mates) = (member, mates)
    }
}

/// Where a gift is on its stage (the approved deck, 2026-11-08): in its box by the coach's hand,
/// floating out of it after 拆开, flown onto the member (立刻穿上), or back in its box (一会儿再说).
enum GiftMoment: Hashable {
    case boxed
    case floating
    case worn
    case stowed
}

/// A card's stage: the squad's scene with the coach and the member standing on it (the coach and
/// the whole squad for a line to everyone). A gift's box pops out of the coach's hand; a challenge
/// has the coach blow its whistle.
struct CoachDeckStage: View {
    let card: CoachPageCard?
    let coachLook: String
    let cast: DeckCast
    var gift: GiftMoment = .boxed
    /// The gift's picture, floating out of its box.
    var giftPicture: AnyView?
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let figure = size.height * 0.62
            ZStack(alignment: .bottom) {
                SceneArt(scene: theme, layer: .day)
                    .frame(width: size.width, height: size.width * SceneArt.designHeight / StageMetrics.designWidth)
                    .frame(width: size.width, height: size.height, alignment: .bottom)
                    .clipped()
                if card?.kind == .board {
                    squadLine(figure: min(figure, size.width / lineWidth(of: 1 + cast.mates.count)))
                } else {
                    pair(figure: figure, width: size.width)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .clipped()
        .accessibilityHidden(true)
    }

    /// How wide a line of the coach and `people` is, in figure heights: the coach, then each on
    /// stage, overlapping; on the smallest phone it is wider than the card, so the figures shrink.
    private func lineWidth(of people: Int) -> Double {
        let onStage = Double(min(people, StageMetrics.squadOnStage))
        return 0.75 + onStage * (0.48 - 0.14) + StageMetrics.squadLineMargin
    }

    /// The coach and the member side by side, a gift's box between them.
    private func pair(figure: Double, width: Double) -> some View {
        HStack(alignment: .bottom, spacing: -figure * 0.12) {
            DeckCoach(look: coachLook, whistles: card?.kind == .challenge)
                .frame(width: figure * 0.75, height: figure)
            if card?.kind == .gift {
                GiftBox(moment: gift, picture: giftPicture, size: figure * 0.26)
                    .padding(.bottom, figure * 0.36)
                    .zIndex(1)
            }
            DeckMember(character: cast.member, wearing: gift == .worn ? card?.gift?.piece : nil)
                .frame(width: figure * 0.68, height: figure * 0.9)
        }
        .padding(.bottom, figure * 0.08)
    }

    /// The coach and the whole squad, for a line to everyone.
    private func squadLine(figure: Double) -> some View {
        HStack(alignment: .bottom, spacing: -figure * 0.14) {
            DeckCoach(look: coachLook, whistles: false)
                .frame(width: figure * 0.75, height: figure)
            let onStage = Array(([cast.member] + cast.mates).prefix(StageMetrics.squadOnStage))
            ForEach(onStage.indices, id: \.self) { index in
                DeckMember(character: onStage[index], wearing: nil)
                    .frame(width: figure * 0.48, height: figure * 0.64)
            }
        }
        .padding(.bottom, figure * 0.08)
    }
}

enum StageMetrics {
    /// The scene art's design width, on which `SceneArt.designHeight` is measured.
    static let designWidth: Double = 390
    /// The most of the squad on a card's stage beside the coach: more don't fit the smallest phone.
    static let squadOnStage = 5
    /// Room left at the line's two ends, in figure heights.
    static let squadLineMargin: Double = 0.15
}

/// The coach standing, idling; on a challenge, blowing its whistle now and then. A coach this
/// build has no character for stands in as a silhouette.
struct DeckCoach: View {
    let look: String
    let whistles: Bool
    @State private var player: CharacterPlayer?
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let player {
                CharacterView(player: player, crop: CoachCanvas.stage)
            } else if !CoachCharacter.exists(look) {
                CoachSilhouette(fill: Color(role: .bgInk, in: theme))
            } else {
                Color.clear
            }
        }
        .task(id: look) {
            guard CoachCharacter.exists(look) else { return }
            guard
                let made = try? CharacterPlayer(
                    figure: CoachCharacter.figure(look), idle: CoachCharacter.clip(.idle, coach: look))
            else { return }
            player = made
            guard whistles, !reduceMotion, let whistle = try? CoachCharacter.clip(.whistle, coach: look) else {
                return
            }
            while !Task.isCancelled {
                try? made.play(whistle)
                try? await Task.sleep(for: .seconds(StageTiming.whistleEvery))
            }
        }
    }
}

/// A member in their own look, idling; `wearing` puts a gift on them, with a hop.
struct DeckMember: View {
    let character: DeckCharacter
    let wearing: String?
    @State private var player: CharacterPlayer?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let player { CharacterView(player: player) } else { Color.clear }
        }
        // Dressed again when the card names someone else, or a gift goes on them.
        .task(id: Dressing(character: character, wearing: wearing)) {
            // Put on once the gift has flown over to them.
            if wearing != nil, !reduceMotion { try? await Task.sleep(for: .seconds(StageTiming.landing)) }
            dress()
        }
    }

    private struct Dressing: Hashable {
        let character: DeckCharacter
        let wearing: String?
    }

    private func dress() {
        var look = character.look
        if let wearing, let slot = PlaceholderCharacter.slot(holding: wearing) { look.variants[slot] = wearing }
        let species = PlaceholderCharacter.species(of: look)
        guard
            let figure = (try? PlaceholderCharacter.figure(wearing: look))
                ?? (try? PlaceholderCharacter.figure(wearing: character.look)),
            let idle = try? PlaceholderCharacter.clip("idle", persona: character.persona, species: species),
            let made = try? CharacterPlayer(figure: figure, idle: idle)
        else { return }
        player = made
        // Put on, the member waves it about.
        if wearing != nil, !reduceMotion,
            let wave = try? PlaceholderCharacter.clip(for: Move.wave, persona: character.persona)
        {
            try? made.play(wave)
        }
    }
}

enum StageTiming {
    /// Seconds between a challenge's whistles.
    static let whistleEvery: Double = 3.2
    /// Seconds of a floating gift's bob, up or down.
    static let bob: Double = 1.2
    /// Seconds a gift takes to reach the member or the box before it fades.
    static let landing: Double = 0.55
}
#endif
