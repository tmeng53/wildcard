/// How a character moves: its own idle loop and check-in cheer. Each persona is a folder of
/// clips (`clips/<id>/idle.json`, `clips/<id>/cheer.json`); every look can play every persona.
/// Display names are UI copy and live in the app's String Catalog, not here.
public struct Persona: Hashable, Sendable {
    public let id: String

    public init(_ id: String) {
        self.id = id
    }

    /// Barely moves: a slow sway, a late and low hop, a nod.
    public static let deadpan = Persona("deadpan")
    /// Can't stand still: bounces in place, then a double jump, the highest of all.
    public static let energetic = Persona("energetic")
    /// Shimmies and poses: spins in the air and lands in a pose.
    public static let showoff = Persona("showoff")
    /// Big sighs and big gestures: leaps with arms wide, then bows as if taking an award.
    public static let drama = Persona("drama")
    /// Keeps to the side: edges away, a small hop, then hides behind both hands and peeks.
    public static let shy = Persona("shy")

    public static let all = [deadpan, energetic, showoff, drama, shy]
}
