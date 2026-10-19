import AvatarDomain

extension PlaceholderCharacter {
    /// The face a person's look picks: eyes, brows, mouth, cheeks and glasses. Animals keep
    /// the rig's default face for now, their coat doing the work.
    public static let faceSlots: [Slot] = ["eyes", "brows", "mouth", "cheeks", "glasses"]

    /// The bodies that are people (a skin tone) rather than animals.
    public static let people: Set<String> = ["peach", "tan"]

    /// The slots the character editor offers a look with this body, in the editor's order:
    /// people get hair and a face, animals neither.
    public static func slots(for body: String) -> [Slot] {
        let worn: [Slot] = ["hat", "top", "bottom", "prop"]
        return people.contains(body) ? ["body", "hair"] + faceSlots + worn : ["body"] + worn
    }
}

extension Outfit {
    /// Puts on a variant, or takes the slot off with nil, which drops its color too: a color
    /// needs a variant to paint. Brows put on without a color of their own take the hair's.
    public mutating func wear(_ variant: String?, in slot: Slot) {
        variants[slot] = variant
        if variant == nil {
            colors[slot] = nil
        } else if slot == "brows", colors["brows"] == nil {
            colors["brows"] = colors["hair"]
        }
    }

    /// Dyes the hair, and the brows with it unless the look gave them a color of their own:
    /// brows follow the hair until someone picks them separately. A look without brows gets
    /// no brow color, since a color needs a variant to paint.
    public mutating func dyeHair(_ color: RGBAColor) {
        if variants["brows"] != nil, colors["brows"] == colors["hair"] { colors["brows"] = color }
        colors["hair"] = color
    }
}
