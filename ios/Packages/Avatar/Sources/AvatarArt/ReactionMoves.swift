import AvatarDomain
import Foundation

extension PlaceholderCharacter {
    /// A move the author's character plays when a teammate reacts to their post, by its id in the
    /// feed's move library (`pump`, `wave`, `happy-hop`, ...): `moves/reactions/<id>.json`, the
    /// same for every persona. Nil for a move not drawn yet; the screen plays the persona's cheer
    /// instead, which is a hop.
    public static func reactionMove(_ id: String) -> Clip? {
        guard id.allSatisfy({ $0.isLetter || $0 == "-" }) else { return nil }
        return try? Clip.decode(file("moves/reactions/\(id).json"))
    }

    /// The ids of the reaction moves drawn so far, sorted.
    public static var reactionMoves: [String] {
        let moves = folder.appendingPathComponent("moves").appendingPathComponent("reactions")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: moves.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
    }
}
