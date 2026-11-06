import AvatarDomain

extension PlaceholderCharacter {
    /// The prop 商店街's shopper carries: a kraft bag in the left fist and a graphite one in the
    /// right, each printed with the Wildcard ticket. The street hands it out, so the editor never
    /// offers it (`variants(for:)` leaves it out).
    public static let shoppingBags = "shopping"

    /// `look` carrying the shopping bags in place of whatever it holds.
    public static func shopping(_ look: Outfit) -> Outfit {
        var shopper = look
        shopper.variants["prop"] = shoppingBags
        shopper.colors["prop"] = nil
        return shopper
    }

    /// Strolling along the street with the bags, looping (`moves/shopping/walk.json`): an
    /// in-place step facing front, the bags swinging behind the hands as weights on a string
    /// would. Dress the look `shopping` first.
    public static func shoppingWalk() throws(AvatarError) -> Clip {
        try Clip.decode(file("moves/shopping/walk.json"))
    }

    /// Stopping at a window with something good in it, once (`moves/shopping/spot.json`): the
    /// bags swing on as the feet plant, a double take, star eyes and two hops with fists up,
    /// then a smile at rest. Starts from the walk's first frame, so start it as a step ends.
    public static func shoppingSpot() throws(AvatarError) -> Clip {
        try Clip.decode(file("moves/shopping/spot.json"))
    }
}
