import AvatarDomain
import DesignSystem

extension PlaceholderCharacter {
    /// Jogging in place while a page loads (character states, 加载; loader design A, 2026-10-24):
    /// the run move (`moves/sports/run.json`), looping, at `Loading.jogTempo` for every persona.
    public static func jogging() throws(AvatarError) -> Clip {
        try Clip.decode(file("moves/sports/run.json")).atTempo(Loading.jogTempo)
    }
}
