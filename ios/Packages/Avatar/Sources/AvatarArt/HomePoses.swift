import AvatarDomain

extension PlaceholderCharacter {
    /// Sitting on the floor on a rest day, looping (`moves/sit.json`): legs out to the sides,
    /// hands by the knees, slow breathing and a little look around. The hand prop is put away.
    /// Played at `persona`'s tempo, like a sport's move.
    public static func sitting(persona: Persona) throws(AvatarError) -> Clip {
        try Clip.decode(file("moves/sit.json")).atTempo(persona.accentTempo)
    }

    /// Holding the 请假条 up in front of the chest, looping (`moves/sign.json`): both hands out to
    /// the card's lower corners, a small sway. The home scene draws the card itself, centred on
    /// the figure at y 249 on its canvas, over the arms. The hand prop is put away.
    public static func holdingSign(persona: Persona) throws(AvatarError) -> Clip {
        try Clip.decode(file("moves/sign.json")).atTempo(persona.accentTempo)
    }

    /// Asleep at night, looping (`moves/sleep.json`): sitting as on a rest day, head dropped to
    /// one side, eyes shut and slow deep breaths. The scene adds the "z z".
    public static func sleeping(persona: Persona) throws(AvatarError) -> Clip {
        try Clip.decode(file("moves/sleep.json")).atTempo(persona.accentTempo)
    }
}
