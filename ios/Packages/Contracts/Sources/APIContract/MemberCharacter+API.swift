import Contracts

// The member's character as the profile and the squad's today carry it. Reading checks the
// nickname as `Contracts` does; the look's ids pass through as data.

extension MemberCharacter {
    public init(_ wire: Components.Schemas.Character) throws(ContractsError) {
        self.init(nickname: try Nickname(wire.nickname), look: CharacterLook(wire.look))
    }
}

extension CharacterLook {
    public init(_ wire: Components.Schemas.Look) {
        self.init(
            persona: wire.persona, variants: wire.variants.additionalProperties,
            colors: wire.colors.additionalProperties)
    }
}

extension Components.Schemas.Character {
    public init(_ character: MemberCharacter) {
        self.init(
            nickname: character.nickname.text,
            look: .init(
                persona: character.look.persona, variants: .init(additionalProperties: character.look.variants),
                colors: .init(additionalProperties: character.look.colors)))
    }
}
