#if os(iOS)
import Contracts

extension SquadSceneView {
    /// A tap, or two, on someone on the stage: a teammate (`mate`) or me (nil). Two taps on a
    /// teammate pat them; on me they do what one does. Nothing while the squad drops in.
    func tap(_ mate: MemberID?, twice: Bool) {
        guard arrival == nil else { return }
        guard let mate else { return tapMe() }
        if twice { doubleTapMate(mate) } else { tapMate(mate) }
    }
}
#endif
