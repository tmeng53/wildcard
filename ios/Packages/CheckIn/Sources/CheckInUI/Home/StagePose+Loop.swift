import AvatarArt
import AvatarDomain
import CheckInDomain

extension StagePose {
    /// What a teammate loops in this pose: sitting on a rest day, holding up their 请假条, asleep
    /// at night, and otherwise the persona's idle, until the sport moves land. The scene draws
    /// the card and the "z z".
    func loop(persona: Persona, species: String?) throws(AvatarError) -> Clip {
        switch self {
        case .sitting: try PlaceholderCharacter.sitting(persona: persona)
        case .holdingSign: try PlaceholderCharacter.holdingSign(persona: persona)
        case .asleep: try PlaceholderCharacter.sleeping(persona: persona)
        case .station, .inPlace, .standing: try PlaceholderCharacter.clip("idle", persona: persona, species: species)
        }
    }
}
