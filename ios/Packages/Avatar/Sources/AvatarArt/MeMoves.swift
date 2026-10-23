import AvatarDomain

extension PlaceholderCharacter {
    /// `look` at a small desk behind a laptop, as 我 shows it. The desk stands in front of the
    /// character, so its hand prop comes off: nothing is held while typing.
    public static func atDesk(_ look: Outfit) -> Outfit {
        var seated = look
        seated.variants["desk"] = "laptop"
        seated.variants["prop"] = nil
        seated.colors["prop"] = nil
        return seated
    }

    /// Typing at the laptop, looping (`moves/typing.json`): a quick bob as the hands tap, and now
    /// and then a rise up to peek over the screen. Dress the look `atDesk` first. Played at
    /// `persona`'s tempo, like a sport's move.
    public static func typing(persona: Persona) throws(AvatarError) -> Clip {
        try Clip.decode(file("moves/typing.json")).atTempo(persona.accentTempo)
    }

    /// About to cry, looping (`moves/teary.json`), for 注销账号: worried brows and a wobbly frown,
    /// a tear welling up at each eye and rolling down, and a sniffle. Any look plays it: the
    /// frown and tears are the rig's own, and the worried brows are each brows variant's `sad`
    /// art (looks without brows cry without them). Played at `persona`'s tempo.
    public static func teary(persona: Persona) throws(AvatarError) -> Clip {
        try Clip.decode(file("moves/teary.json")).atTempo(persona.accentTempo)
    }
}
