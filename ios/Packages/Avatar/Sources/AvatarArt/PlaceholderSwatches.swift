import AvatarDomain
import DesignSystem

extension PlaceholderCharacter {
    /// The preset colors a look can give a slot while it wears `variant`, for the character
    /// editor's swatches, besides the art's own (its 原色): skin or fur for `body`, then `hair`,
    /// `eyes` and `brows` from the design system's character tones, and each piece of clothing's
    /// own colors from `editor.json`. Empty for slots that keep their art's colors (props,
    /// mouths, cheeks, glasses) and for a variant without `tones.json`.
    public static func swatches(for slot: Slot, wearing variant: String) -> [RGBAColor] {
        guard BundledArt().text(at: "\(slot)/\(variant)/tones.json") != nil else { return [] }
        return switch slot.description {
        case "body": bodySpecies[variant].flatMap { coats[$0] } ?? []
        case "hair", "brows": hair
        case "eyes": eyes
        default: Array((clothes[slot]?[variant] ?? []).dropFirst())
        }
    }

    /// Skin for people, fur for animals, by species. A coat whose pattern is the point has no
    /// `tones.json`, so it keeps its art's colors.
    static let coats = ["person": skin, "cat": catFur, "dog": dogFur, "rabbit": rabbitFur, "bear": bearFur]

    /// The species of every body in `editor.json`. A broken `editor.json` fails the tests, so
    /// here it only leaves the bodies without swatches.
    static let bodySpecies: [String: String] = {
        let species = (try? editorChoices().species) ?? []
        return Dictionary(species.flatMap { kind in kind.bodies.map { ($0, kind.id) } }) { first, _ in first }
    }()

    /// Every piece of clothing's colors in `editor.json`, by slot and variant, its art's own first.
    static let clothes: [Slot: [String: [RGBAColor]]] = {
        let wear = (try? editorChoices().wear) ?? [:]
        return wear.mapValues { pieces in
            Dictionary(pieces.map { ($0.id, $0.swatches) }) { first, _ in first }
        }
    }()

    static let skin = colors(Palette.skinTones)
    static let catFur = colors(Palette.catFur)
    static let bearFur = colors(Palette.bearFur)
    static let dogFur = colors(Palette.dogFur)
    static let rabbitFur = colors(Palette.rabbitFur)
    static let hair = colors(Palette.hairColors)
    static let eyes = colors(Palette.eyeColors)

    private static func colors(_ palette: [SRGBColor]) -> [RGBAColor] {
        palette.map { RGBAColor(red: $0.red, green: $0.green, blue: $0.blue) }
    }
}
