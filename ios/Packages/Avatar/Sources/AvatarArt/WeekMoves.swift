import AvatarDomain
import Contracts

extension PlaceholderCharacter {
    /// What a week's poster character loops for its plan (`PlanDay.mostPlanned(in:)`): the kit
    /// and move of the training planned most (the warm-up for a training day with no sport
    /// named), or sitting on the floor in its own look for a week of rest.
    public static func weekLoop(
        for days: [PlanDay], look: Outfit, persona: Persona
    ) throws(AvatarError) -> (outfit: Outfit, clip: Clip) {
        switch PlanDay.mostPlanned(in: days) {
        case .rest:
            return (look, try sitting(persona: persona))
        case .train(let activity):
            let kits = try sportKits()
            let kit = activity.map(kits.kit(for:)) ?? kits.warmUp
            return (kit.dress(look), try move(for: kit, persona: persona))
        }
    }
}
