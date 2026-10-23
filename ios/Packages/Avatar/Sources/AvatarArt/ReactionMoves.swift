import AvatarDomain
import Foundation

extension PlaceholderCharacter {
    /// A move the author's character plays when a teammate reacts to their post, by its id in the
    /// feed's move library (`heart`, `flex`, `chin-up`, ...): `moves/reactions/<id>.json`, the
    /// same for every persona. Nil for a move not drawn yet; the screen plays the persona's cheer
    /// instead, which is a hop.
    public static func reactionMove(_ id: String) -> Clip? {
        guard id.allSatisfy({ $0.isLetter || $0 == "-" }) else { return nil }
        return try? Clip.decode(file("moves/reactions/\(id).json"))
    }

    /// `persona`'s own take on the move, `moves/reactions/<persona>/<id>.json`, at its tempo
    /// (`accentTempo`): 淡人 reacts late, barely moves, eyes half shut, then nods; 高能量 bounces
    /// through it and hops twice more; 显眼包 sways to the camera and ends on a pose; 戏精 gasps,
    /// goes slow motion and bows; 社恐 plays it small while edging away, then hides its face.
    /// Nil for a move not drawn yet.
    public static func reactionMove(_ id: String, persona: Persona) -> Clip? {
        guard id.allSatisfy({ $0.isLetter || $0 == "-" }),
            let clip = try? Clip.decode(file("moves/reactions/\(persona.rawValue)/\(id).json"))
        else { return nil }
        return try? clip.atTempo(persona.accentTempo)
    }

    /// The ids of the reaction moves drawn so far, sorted.
    public static var reactionMoves: [String] {
        let moves = folder.appendingPathComponent("moves").appendingPathComponent("reactions")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: moves.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
    }
}
