import AvatarArt
import AvatarDomain

/// Looks the tests and previews run over, beside the app's `PlaceholderCharacter.lifter`.
public enum Looks {
    /// A cat in a cap and tank top, with a tennis racket.
    public static let cat = Outfit([
        "body": "cat", "hat": "cap", "top": "tank", "bottom": "greenshorts", "prop": "racket",
    ])
    /// A bear in a hoodie and leggings, hands free.
    public static let bear = Outfit(["body": "bear", "top": "hoodie", "bottom": "leggings"])
    /// Deeper skin, sharp eyes, bold brows, a smirk and freckles, a headband, a jersey and a racket.
    public static let athlete = Outfit(
        [
            "body": "peach", "hair": "buzz", "eyes": "sharp", "brows": "bold", "mouth": "smirk", "cheeks": "freckles",
            "hat": "headband", "top": "jersey", "bottom": "shorts", "prop": "racket",
        ],
        colors: ["body": RGBAColor(red: 0xD9, green: 0xA2, blue: 0x7A)])
    /// Four looks from the same rig: different species, faces, hair, hats, clothes and props.
    /// Any look can play any persona's clips.
    public static let squad = [PlaceholderCharacter.lifter, cat, bear, athlete]
}
