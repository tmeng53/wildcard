import AvatarArt
import AvatarDomain
import RecapDomain

extension StoryClip {
    /// The character's clip for this, at `persona`'s tempo: an award move by its id
    /// (`NamedMove`: a shared move, 躺平, a reaction move, a sport kit's move), a meal as the
    /// check-in eats it, the toss's and the stack's own parts. A trained day plays its sport's
    /// kit move, which the caller picks; here, and for a move the art doesn't have, it is the
    /// persona's cheer.
    func art(persona: Persona, species: String?) throws(AvatarError) -> Clip {
        switch self {
        case .award(let move):
            guard let named = NamedMove(move.rawValue) else { break }
            return try PlaceholderCharacter.clip(for: named, persona: persona, species: species)
        case .eat(let meal): return try PlaceholderCharacter.clip(for: Self.checkIn(meal), persona: persona)
        case .tossThrower: return try PlaceholderCharacter.toss().roles[0].clip
        case .tossFlyer: return try PlaceholderCharacter.toss().roles[1].clip
        case .stackTop: return try PlaceholderCharacter.stack().roles[0].clip
        case .stackBottom: return try PlaceholderCharacter.stack().roles[1].clip
        case .sport: break
        }
        return try PlaceholderCharacter.clip("cheer", persona: persona, species: species)
    }

    /// `look` holding what this needs: the bowl or the boba for a meal, as the check-in holds
    /// it; a sport's prop for its award move; the look as it is for the rest. (A trained day's
    /// kit is the caller's, as for the clip.)
    func dressing(_ look: Outfit) -> Outfit {
        switch self {
        case .eat(let meal): PlaceholderCharacter.dressed(look, for: Self.checkIn(meal))
        case .award(let move): NamedMove(move.rawValue)?.kit?.dress(look) ?? look
        default: look
        }
    }

    private static func checkIn(_ meal: Meals.Meal) -> CheckInMove {
        switch meal {
        case .healthy: .healthyMeal
        case .cheat: .treatMeal
        }
    }
}

/// The award a character wears, the rig's own parts: the medal on the chest, the crown dropping
/// onto the head.
struct Regalia: Hashable {
    var medal = false
    /// How far the crown has fallen, from 0 (out of sight above) to 1 (on the head); nil for none.
    var crown: Double?

    static let none = Regalia()

    /// How far above the head the crown starts, in canvas points.
    static let crownDropHeight = 260.0

    /// Shows the medal and the crown on `pose`; the crown fades in over its first sixth of the
    /// fall.
    func dress(_ pose: inout Pose, on figure: Figure) {
        if medal, let index = figure.parts.firstIndex(where: { $0.id == "medal" }) {
            pose.parts[index].opacity = 1
        }
        if let fallen = crown, let index = figure.parts.firstIndex(where: { $0.id == "award" }) {
            pose.parts[index].opacity = min(fallen * 6, 1)
            pose.parts[index].y -= Self.crownDropHeight * (1 - fallen)
        }
    }
}

/// The area a story character is drawn in, in canvas points: the rig's 240 × 320 canvas with
/// room above for the toss, the stack's jump and the crown's drop, to the left for lying flat,
/// and to the right for the stack's top one, who ends `stackTopLandsAt` along.
enum StoryRoom {
    static let minX = -60.0
    static let minY = -320.0
    static let maxX = 520.0
    static let maxY = 340.0
}
