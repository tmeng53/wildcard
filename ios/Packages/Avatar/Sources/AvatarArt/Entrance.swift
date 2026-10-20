import AvatarDomain

extension PlaceholderCharacter {
    /// 上场, a new member's entrance into the squad: runs in from the right, skids to a stop,
    /// crouches, star-jumps and lands squashed on its spot, back at rest. Every look and
    /// persona plays the same entrance; the member's persona shows in the `welcome` that follows.
    ///
    /// The root carries the character across the stage, so this is the one clip that leaves the
    /// canvas: it starts 911 points to the right of where it lands and jumps 329 high, with the
    /// shadow keeping to the floor. A screen draws it over the stage (`CharacterCanvas`'s `crop`
    /// wider and taller than the canvas) and fits the landing spot where the figure belongs.
    /// Play it without blending (`CharacterPlayer.play(_:blending: false)`): it starts off stage,
    /// and a blend from the character standing on its spot would slide it out there first.
    public static func entrance() throws(AvatarError) -> Clip {
        try Clip.decode(file("moves/entrance.json"))
    }
}
