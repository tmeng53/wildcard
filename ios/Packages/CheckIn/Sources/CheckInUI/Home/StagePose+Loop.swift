import AvatarArt
import AvatarDomain
import CheckInDomain
import Contracts
import SportsUI

extension PlaceholderCharacter {
    /// The sports' kits, read once, for every character on the home.
    static let shippedKits = try? sportKits()
}

extension StagePose {
    /// What a teammate loops in this pose: sitting on a rest day, holding up their 请假条, asleep
    /// at night, and otherwise the persona's idle. The scene draws the card and the "z z".
    func loop(persona: Persona, species: String?) throws(AvatarError) -> Clip {
        switch self {
        case .sitting: try PlaceholderCharacter.sitting(persona: persona)
        case .holdingSign: try PlaceholderCharacter.holdingSign(persona: persona)
        case .asleep: try PlaceholderCharacter.sleeping(persona: persona)
        case .station, .inPlace, .standing: try PlaceholderCharacter.clip("idle", persona: persona, species: species)
        }
    }

    /// What a teammate wears and loops in this pose. Training, they hold their sport's kit and
    /// loop its move, from the same `kits.json` and `move(for:)` as my own character; anyone
    /// else wears `look` and loops `loop(persona:species:)`.
    func dress(
        _ look: Outfit, trained activity: Activity?, persona: Persona, species: String?,
        catalog: SportCatalog = SportList.shared.catalog
    ) throws(AvatarError) -> (outfit: Outfit, loop: Clip) {
        if let activity, let kit = kit(for: activity, in: catalog),
            let move = try? PlaceholderCharacter.move(for: kit, persona: persona)
        {
            return (kit.dress(look), move)
        }
        return (look, try loop(persona: persona, species: species))
    }

    /// The kit a teammate trains `activity` in here: their sport's on its station; in place,
    /// the same, except that swimmers and climbers away from water and wall warm up.
    private func kit(for activity: Activity, in catalog: SportCatalog) -> SportKit? {
        guard let kits = PlaceholderCharacter.shippedKits else { return nil }
        let kit = kits.kit(for: activity, in: catalog)
        switch self {
        case .station: return kit
        case .inPlace: return Self.needsVenue.contains(kit.id) ? kits.fallback : kit
        case .sitting, .holdingSign, .asleep, .standing: return nil
        }
    }

    /// Kits whose move needs the scene's water or wall.
    private static let needsVenue: Set<String> = ["swim", "climb"]
}
