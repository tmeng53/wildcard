import AvatarDomain

/// A move a character plays by its id, as the server names it (the weekly awards' AI picks one
/// per title): the persona's own `cheer`, `flat` (躺平), a move every character shares (`Move`),
/// one of 动态's reaction moves, or a sport kit's move, played holding that kit's prop. Every
/// move the art has is here by its file or kit, so a new move file or kit is a new id with no
/// code; the API's award moves are checked against the same art (`award-moves.test.ts`).
public enum NamedMove: Hashable, Sendable {
    case cheer
    case flat
    case shared(Move)
    case reaction(String)
    /// The kit's move from `kits.json`, the one source of what each sport plays.
    case kit(SportKit)

    /// Shared moves first, then reactions, then kits (a kit called `warmup` is the shared move
    /// of the same name); nil for an id the art has no move for, which plays the cheer.
    public init?(_ id: String) {
        if id == "cheer" {
            self = .cheer
        } else if id == "flat" {
            self = .flat
        } else if let move = Move(rawValue: id) {
            self = .shared(move)
        } else if Self.reactions.contains(id) {
            self = .reaction(id)
        } else if let kit = Self.kits[id] {
            self = .kit(kit)
        } else {
            return nil
        }
    }

    // Read once: screens look a move up while they draw.
    private static let reactions = Set(PlaceholderCharacter.reactionMoves)
    private static let kits = Dictionary(
        ((try? PlaceholderCharacter.sportKits().kits) ?? []).map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first })

    /// Every id it plays, sorted: what the weekly awards may pick from.
    public static var all: [String] {
        Array(Set(["cheer", "flat"] + Move.allCases.map(\.rawValue) + reactions + kits.keys)).sorted()
    }

    /// The kit to wear while the move plays: a kit's own; none for the rest.
    public var kit: SportKit? {
        if case .kit(let kit) = self { kit } else { nil }
    }
}

extension PlaceholderCharacter {
    /// `move` at `persona`'s tempo: a reaction in the persona's own take where it has one, a
    /// kit's move looping as that sport trains (`move(for:persona:)`).
    public static func clip(for move: NamedMove, persona: Persona, species: String?) throws(AvatarError) -> Clip {
        switch move {
        case .cheer: return try clip("cheer", persona: persona, species: species)
        case .flat: return try lyingFlat(persona: persona)
        case .shared(let shared): return try clip(for: shared, persona: persona)
        case .reaction(let id):
            if let own = reactionMove(id, persona: persona) { return own }
            guard let shared = reactionMove(id) else { throw .missingFile("moves/reactions/\(id).json") }
            return try shared.atTempo(persona.accentTempo)
        case .kit(let kit): return try self.move(for: kit, persona: persona)
        }
    }
}
