import AvatarDomain
import DesignSystem

extension PlaceholderCharacter {
    /// The preset colors a look can give a slot while it wears `variant`, for the character
    /// editor's swatches: skin or fur for `body`, then `hair`, `top` and `bottom`. Empty for
    /// slots that keep their art's colors (hats, props) and for a variant without
    /// `tones.json`. Clothes take the design system's palette; skin, fur and hair take
    /// natural tones, which the palette doesn't have.
    public static func swatches(for slot: Slot, wearing variant: String) -> [RGBAColor] {
        guard BundledArt().text(at: "\(slot)/\(variant)/tones.json") != nil else { return [] }
        return switch (slot.description, variant) {
        case ("body", "peach"), ("body", "tan"): skin
        case ("body", "cat"): catFur
        case ("body", "bear"): bearFur
        case ("hair", _): hair
        case ("top", _): tops
        case ("bottom", _): bottoms
        default: []
        }
    }

    /// Light to deep, including the peach and tan bodies' own tones.
    static let skin = hexes(["#F9DCC4", "#F5CDAE", "#E8B48F", "#D9A27A", "#B97F57", "#8D5A3B", "#5E3B27"])
    /// Orange tabby (the art's own), cream, gray, black, white and brown tabby.
    static let catFur = hexes(["#F2A65A", "#F6E6CC", "#A3A7B0", "#4A4650", "#FBFAF6", "#C9874F"])
    /// Brown (the art's own), dark brown, honey, polar white, black and grizzly.
    static let bearFur = hexes(["#B98563", "#7E5236", "#D9B07E", "#F2EFE8", "#3F393B", "#A8927E"])
    /// Black, dark brown, brown, light brown, blonde, auburn and silver.
    static let hair = hexes(["#2A2333", "#4A2F25", "#6B4330", "#B07B4A", "#E2BF74", "#A2452F", "#C4C2CA"])
    static let tops = colors([
        Palette.cobalt, Palette.mint, Palette.trackSignature, Palette.lavender, Palette.honey,
        Palette.poolSignature, Palette.climbingSignature, Palette.graphite,
    ])
    static let bottoms = colors([
        Palette.graphite, Palette.inkSecondary, Palette.cobalt, Palette.mint, Palette.tennisSignature,
        Palette.climbingSignature, Palette.trackSignature, Palette.lavender,
    ])

    private static func hexes(_ texts: [String]) -> [RGBAColor] {
        texts.compactMap(RGBAColor.init(hex:))
    }

    private static func colors(_ palette: [SRGBColor]) -> [RGBAColor] {
        palette.map { RGBAColor(red: $0.red, green: $0.green, blue: $0.blue) }
    }
}
