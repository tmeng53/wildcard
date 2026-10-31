import AvatarDomain

/// What a character does for each kind of check-in, once: the dumbbell's own lift (练了), eats a
/// salad (健康餐), sneaks a boba (坦白放纵餐) or nods off on their feet (今日请假条).
public enum CheckInMove: String, CaseIterable, Sendable {
    case workout, healthyMeal, treatMeal, excuse
}

extension PlaceholderCharacter {
    /// `look` holding what `move` needs: the dumbbell for a workout, the food for a meal (both
    /// hands on it, so the hand prop comes off), nothing for a nap. The saved look never changes.
    public static func dressed(_ look: Outfit, for move: CheckInMove) -> Outfit {
        var dressed = look
        dressed.colors["prop"] = nil
        switch move {
        case .workout: dressed.variants["prop"] = "dumbbell"
        case .healthyMeal: (dressed.variants["prop"], dressed.variants["food"]) = (nil, "bowl")
        case .treatMeal: (dressed.variants["prop"], dressed.variants["food"]) = (nil, "boba")
        case .excuse: dressed.variants["prop"] = nil
        }
        return dressed
    }

    /// `move` once, for a look `dressed(_:for:)` it: the dumbbell's own move for a workout, the
    /// rest from `moves/checkins/`. Meals have a clip per persona: a bite takes a piece out of the
    /// food, then the cheeks puff while chewing. The lift and the nap play at `persona`'s tempo,
    /// like a sport's move.
    public static func clip(for move: CheckInMove, persona: Persona) throws(AvatarError) -> Clip {
        switch move {
        case .workout: try Clip.decode(file("moves/props/dumbbell.json")).atTempo(persona.accentTempo)
        case .healthyMeal: try Clip.decode(file("moves/checkins/healthy-\(persona.rawValue).json"))
        case .treatMeal: try Clip.decode(file("moves/checkins/treat-\(persona.rawValue).json"))
        case .excuse: try Clip.decode(file("moves/checkins/doze.json")).atTempo(persona.accentTempo)
        }
    }
}
