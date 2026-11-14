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
    /// Everyone in the squad by id, the member too, for a coach message naming who stands there.
    public let byMember: [MemberID: DeckCharacter]

    public init(member: DeckCharacter, mates: [DeckCharacter], byMember: [MemberID: DeckCharacter] = [:]) {
        (self.member, self.mates, self.byMember) = (member, mates, byMember)
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
/// has the coach blow its whistle. A coach message says who stands there (the coach alone, with
/// the member, with the squad in two rows of four past four, or with members it names), the move
/// the coach plays and the scene behind them.
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
                SceneArt(scene: scene, layer: .day)
                    .frame(width: size.width, height: size.width * SceneArt.designHeight / StageMetrics.designWidth)
                    .frame(width: size.width, height: size.height, alignment: .bottom)
                    .clipped()
                if let messageStage {
                    message(messageStage, figure: figure, width: size.width)
                } else if card?.kind == .board {
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

    /// The stage of a coach message's card as it stands now; nil for any other card.
    private var messageStage: CoachMessage.Stage? {
        guard let message = card?.message else { return nil }
        return message.card(at: message.place.path)?.stage
    }

    /// The scene a coach message names, else the squad's.
    private var scene: SceneTheme {
        messageStage?.scene.flatMap(SceneTheme.init(rawValue:)) ?? theme
    }

    /// A coach message's stage: who it says stands with the coach, the coach playing its move.
    @ViewBuilder private func message(_ stage: CoachMessage.Stage, figure: Double, width: Double) -> some View {
        let move = stage.move.flatMap(CoachCharacter.Move.init(rawValue:))
        switch stage.cast {
        case .coach:
            DeckCoach(look: coachLook, whistles: false, move: move)
                .frame(width: figure * 0.75, height: figure)
                .padding(.bottom, figure * 0.08)
        case .coachAndMe:
            pair(figure: figure, width: width, move: move)
        case .coachAndSquad:
            crowd([cast.member] + cast.mates, figure: figure, width: width, move: move)
        case .members(let members):
            crowd(members.compactMap { cast.byMember[$0] }, figure: figure, width: width, move: move)
        }
    }

    /// The coach and `people`: in a line up to four, else four in front and the rest, up to four,
    /// smaller and higher behind them (Tracy, 2026-11-12).
    @ViewBuilder private func crowd(
        _ people: [DeckCharacter], figure: Double, width: Double, move: CoachCharacter.Move?
    ) -> some View {
        if people.count <= StageMetrics.frontRow {
            squadLine(figure: min(figure, width / lineWidth(of: 1 + people.count)), people: people, move: move)
        } else {
            rows(people, figure: min(figure, width / lineWidth(of: 1 + StageMetrics.frontRow)), move: move)
        }
    }

    /// Two rows: the coach and four in front, up to four more behind, smaller and raised so their
    /// heads show over the front row.
    private func rows(_ people: [DeckCharacter], figure: Double, move: CoachCharacter.Move?) -> some View {
        let front = Array(people.prefix(StageMetrics.frontRow))
        let back = Array(people.dropFirst(StageMetrics.frontRow).prefix(StageMetrics.frontRow))
        return ZStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: -figure * 0.1) {
                ForEach(back.indices, id: \.self) { index in
                    DeckMember(character: back[index], wearing: nil)
                        .frame(width: figure * 0.4, height: figure * 0.53)
                }
            }
            .padding(.leading, figure * 0.6)
            .padding(.bottom, figure * 0.24)
            squadLine(figure: figure, people: front, move: move)
        }
    }

    /// The coach and the member side by side, a gift's box between them.
    private func pair(figure: Double, width: Double, move: CoachCharacter.Move? = nil) -> some View {
        HStack(alignment: .bottom, spacing: -figure * 0.12) {
            DeckCoach(look: coachLook, whistles: card?.kind == .challenge, move: move)
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

    /// The coach and the whole squad, for a line to everyone; or the coach and `people`.
    private func squadLine(
        figure: Double, people: [DeckCharacter]? = nil, move: CoachCharacter.Move? = nil
    ) -> some View {
        HStack(alignment: .bottom, spacing: -figure * 0.14) {
            DeckCoach(look: coachLook, whistles: false, move: move)
                .frame(width: figure * 0.75, height: figure)
            let onStage = Array((people ?? [cast.member] + cast.mates).prefix(StageMetrics.squadOnStage))
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
    /// How many stand in a coach message's front row; the rest stand behind.
    static let frontRow = 4
    /// Room left at the line's two ends, in figure heights.
    static let squadLineMargin: Double = 0.15
}

/// The coach standing, idling; on a challenge, blowing its whistle now and then; with a `move`,
/// playing it once (a move that loops, such as crying, instead of its idle). A coach this build
/// has no character for stands in as a silhouette.
struct DeckCoach: View {
    let look: String
    let whistles: Bool
    var move: CoachCharacter.Move?
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
        .task(id: "\(look)/\(move?.rawValue ?? "")") {
            guard CoachCharacter.exists(look) else { return }
            let rest = move.flatMap { $0.loops ? $0 : nil } ?? .idle
            guard
                let made = try? CharacterPlayer(
                    figure: CoachCharacter.figure(look), idle: CoachCharacter.clip(rest, coach: look))
            else { return }
            player = made
            if let move, !move.loops, !reduceMotion, let clip = try? CoachCharacter.clip(move, coach: look) {
                try? made.play(clip)
            }
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
