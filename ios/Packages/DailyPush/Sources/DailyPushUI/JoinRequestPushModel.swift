#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import Contracts
import DailyPushDomain
import Foundation
import Observation

/// The captain's push about a request to join, long-pressed: the answer and the asker's
/// character, who cheers once the captain taps 同意.
@MainActor @Observable
public final class JoinRequestPushModel {
    let answer: JoinRequestAnswer
    /// When the push arrived, shown in the header.
    let arrived: Date
    /// The asker standing, or nil when the art can't be drawn.
    @ObservationIgnored let player: CharacterPlayer?
    /// Until when the cheer plays; the character holds still otherwise.
    private(set) var cheering: Date?
    @ObservationIgnored private let persona: Persona
    @ObservationIgnored private let species: String?
    @ObservationIgnored private let now: () -> Date

    public init(answer: JoinRequestAnswer, arrived: Date, now: @escaping () -> Date = { Date() }) {
        self.answer = answer
        self.arrived = arrived
        self.now = now
        let look = answer.push.look
        let outfit = look.map(Outfit.init) ?? PlaceholderCharacter.lifter
        persona = look.map(Persona.init) ?? .energetic
        species = PlaceholderCharacter.species(of: outfit)
        player = (try? PlaceholderCharacter.figure(wearing: outfit)).flatMap {
            try? CharacterPlayer(figure: $0, idle: .still, now: now())
        }
    }

    var push: JoinRequestPush { answer.push }

    /// The captain taps 同意 (`approve`) or 拒绝. A yes that went through cheers.
    func reply(approve: Bool) {
        Task {
            await answer.answer(approve: approve)
            if answer.state == .approved { cheer() }
        }
    }

    /// The cheer has played: the character holds still again.
    func cheered() {
        if let cheering, cheering <= now() { self.cheering = nil }
    }

    private func cheer() {
        guard let player, let clip = try? PlaceholderCharacter.clip("cheer", persona: persona, species: species)
        else { return }
        let start = now()
        try? player.play(clip, now: start)
        cheering = start.addingTimeInterval(clip.duration)
    }
}
#endif
