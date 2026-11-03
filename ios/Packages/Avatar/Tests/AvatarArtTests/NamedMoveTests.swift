import AvatarArt
import AvatarDomain
import Testing

/// Every move id the art has plays its own clip on any look, the sport moves holding their kit's
/// prop; an id the art doesn't have is nil, for the screen's cheer.
@Test(arguments: Persona.allCases)
func everyNamedMovePlays(persona: Persona) throws {
    #expect(NamedMove.all.count > 25)
    for id in NamedMove.all {
        let move = try #require(NamedMove(id), "\(id)")
        var look = PlaceholderCharacter.lifter
        if let kit = move.kit { look = kit.dress(look) }
        let figure = try PlaceholderCharacter.figure(wearing: look)
        _ = try figure.bind(PlaceholderCharacter.clip(for: move, persona: persona, species: nil))
    }
    #expect(NamedMove("moonwalk") == nil)
}

@Test func namedMovesResolveByKind() throws {
    #expect(NamedMove("cheer") == .cheer)
    #expect(NamedMove("flat") == .flat)
    #expect(NamedMove("pump") == .shared(.pump))
    // The shared warm-up wins over the warm-up kit.
    #expect(NamedMove("warmup") == .shared(.warmup))
    #expect(NamedMove("chin-up") == .reaction("chin-up"))
    let swim = try #require(NamedMove("swim")?.kit)
    #expect(swim.prop == "goggles")
    #expect(NamedMove("pump")?.kit == nil)
    for id in ["heart", "flex", "laugh-bend", "drool", "shocked", "pout", "bump", "poked", "tennis", "climb"] {
        #expect(NamedMove.all.contains(id), "\(id)")
    }
}
