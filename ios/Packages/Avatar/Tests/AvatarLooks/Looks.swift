import AvatarArt
import AvatarDomain

/// Looks the tests and previews run over, beside the app's `PlaceholderCharacter.lifter`.
public enum Looks {
    /// A cat in DEUCE CLUB's visor, polo, pleated skirt and court shoes, with a tennis racket.
    public static let cat = Outfit([
        "body": "cat", "hat": "deuce-visor", "top": "deuce-polo", "bottom": "deuce-skirt", "shoes": "deuce-court",
        "prop": "racket",
    ])
    /// A bear in MOSSWAY's anorak, cargo shorts, trail shoes and sling bag, hands free.
    public static let bear = Outfit([
        "body": "bear", "hat": "moss-bucket", "top": "moss-anorak", "bottom": "moss-cargo", "shoes": "moss-trail",
        "acc": "moss-sling",
    ])
    /// Deeper skin, sharp eyes, bold brows, a smirk and freckles, NO LOOK's cap, jersey, shorts and
    /// high-tops, and a racket.
    public static let athlete = Outfit(
        [
            "body": "peach", "hair": "buzz", "eyes": "sharp", "brows": "bold", "mouth": "smirk", "cheeks": "freckles",
            "hat": "nolook-backcap", "top": "nolook-jersey", "bottom": "nolook-shorts", "shoes": "nolook-hightop",
            "prop": "racket",
        ],
        colors: ["body": RGBAColor(red: 0xD9, green: 0xA2, blue: 0x7A)])
    /// Four looks from the same rig: different species, faces, hair, hats, clothes and props.
    /// Any look can play any persona's clips.
    public static let squad = [PlaceholderCharacter.lifter, cat, bear, athlete]

    /// The species `editor.json` groups a look's body under, whose moves its clips play with.
    public static func species(of look: Outfit) -> String? {
        PlaceholderCharacter.species(of: look)
    }
}
