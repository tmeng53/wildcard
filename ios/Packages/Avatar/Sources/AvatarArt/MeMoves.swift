import AvatarDomain

extension PlaceholderCharacter {
    /// The pencil 意见反馈's character writes with: held only at that desk, never an editor pick.
    public static let writingPencil = "pencil"

    /// `look` at a small desk behind a laptop, as 我 shows it. The desk stands in front of the
    /// character, so its hand prop comes off: nothing is held while typing.
    public static func atDesk(_ look: Outfit) -> Outfit {
        var seated = look
        seated.variants["desk"] = "laptop"
        seated.variants["prop"] = nil
        seated.colors["prop"] = nil
        return seated
    }

    /// `look` at the same desk writing in an open notebook, pencil in hand, as 意见反馈 shows it.
    public static func atDeskWriting(_ look: Outfit) -> Outfit {
        var seated = look
        seated.variants["desk"] = "notebook"
        seated.variants["prop"] = writingPencil
        seated.colors["prop"] = nil
        return seated
    }

    /// Writing in the notebook, looping (`moves/writing.json`): the pencil hand scribbles with the
    /// head bowed over the page, then the pencil lifts and the eyes look up to think. Dress the
    /// look `atDeskWriting` first. Played at `persona`'s tempo.
    public static func writing(persona: Persona) throws(AvatarError) -> Clip {
        try Clip.decode(file("moves/writing.json")).atTempo(persona.accentTempo)
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
