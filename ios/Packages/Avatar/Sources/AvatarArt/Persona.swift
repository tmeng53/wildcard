/// How a character moves: its own idle loop and check-in cheer. Each persona is a folder of
/// clips (`clips/<raw value>/idle.json`, `clips/<raw value>/cheer.json`); every look can play
/// every persona. Display names are UI copy and live in the app's String Catalog, not here.
public enum Persona: String, CaseIterable, Sendable {
    /// Barely moves: a slow sway, a late and low hop, a nod.
    case deadpan
    /// Can't stand still: bounces in place, then a double jump, the highest of all.
    case energetic
    /// Shimmies and poses: spins in the air and lands in a pose.
    case showoff
    /// Big sighs and big gestures: leaps with arms wide, then bows as if taking an award.
    case drama
    /// Keeps to the side: edges away, a small hop, then hides behind both hands and peeks.
    case shy
}
