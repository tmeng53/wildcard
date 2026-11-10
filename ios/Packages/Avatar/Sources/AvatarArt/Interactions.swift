import AvatarDomain

/// Teammates doing something together: each one's clip, where they stand and when they start,
/// as designed. Everyone faces right and stands on the same ground line; `offset` is in canvas
/// points from the one who starts it. The clips leave the canvas (a hop over, a toss up high),
/// so draw them with a `crop` around the whole group, and play each without blending.
public struct Interaction: Sendable {
    /// One teammate's part in it.
    public struct Role: Sendable {
        public let clip: Clip
        /// Where they stand, in canvas points to the right of the one who starts it.
        public let offset: Double
        /// How long after the start their clip begins, in seconds.
        public let delay: Double
    }

    /// The one who starts it first.
    public let roles: [Role]
}

extension PlaceholderCharacter {
    /// 撞头 with a 社恐: the 社恐 ducks out of the way just in time, so the other bonks into thin
    /// air and stumbles; the 社恐 peeks and shuffles back (`bump-miss.json`, `dodge.json`).
    public static func bumpDodged() throws(AvatarError) -> Interaction {
        try Interaction(roles: [
            .init(clip: interaction("bump-miss"), offset: 0, delay: 0),
            .init(clip: interaction("dodge"), offset: 240, delay: 0),
        ])
    }

    /// 抛高高: two teammates crouch and push the one between them up into the air, who lands
    /// back on their spot (`toss-thrower.json` for both sides, `toss-flyer.json`).
    public static func toss() throws(AvatarError) -> Interaction {
        let thrower = try interaction("toss-thrower")
        return try Interaction(roles: [
            .init(clip: thrower, offset: 0, delay: 0),
            .init(clip: interaction("toss-flyer"), offset: 160, delay: 0),
            .init(clip: thrower, offset: 320, delay: 0),
        ])
    }

    /// 叠罗汉: one hops onto the other's big head; the bottom one squashes and holds, both raise
    /// their arms, then the top one jumps down on the far side, `stackTopLandsAt` points from
    /// where it started, and stays there (`stack-top.json`, `stack-bottom.json`).
    public static func stack() throws(AvatarError) -> Interaction {
        try Interaction(roles: [
            .init(clip: interaction("stack-top"), offset: 0, delay: 0),
            .init(clip: interaction("stack-bottom"), offset: 150, delay: 0),
        ])
    }

    /// How far right of its start the stack's top one ends up.
    public static let stackTopLandsAt = 250.0

    /// How far past the canvas the stack's top one reaches, in canvas points: up 300 on its
    /// jump with its arms raised over its head, and over to the right by `stackTopLandsAt` with
    /// its whole body. A screen that plays it draws the figure with this much room above and to
    /// either side (a figure facing left is mirrored), or the top one is cut off on the head.
    public static let stackReachAbove = 400.0
    public static let stackReachSideways = 280.0

    private static func interaction(_ name: String) throws(AvatarError) -> Clip {
        try Clip.decode(file("moves/interactions/\(name).json"))
    }
}
