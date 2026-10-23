import AvatarArt
import AvatarDomain
import Contracts
import Testing

@Test func aLookReadsAsTheOutfitAndPersonaItNames() {
    let look = CharacterLook(
        persona: "shy", variants: ["body": "cat-calico", "top": "hoodie"], colors: ["top": "#3A7BD5"])

    #expect(
        Outfit(look)
            == Outfit(
                ["body": "cat-calico", "top": "hoodie"], colors: ["top": RGBAColor(red: 58, green: 123, blue: 213)]))
    #expect(Persona(look) == .shy)
}

@Test func anOutfitWritesItsSwatchesAsCapitalHex() {
    let outfit = Outfit(
        ["body": "person-2", "hair": "bob"],
        colors: ["hair": RGBAColor(red: 10, green: 171, blue: 255), "body": RGBAColor(red: 0, green: 0, blue: 0)])

    #expect(
        CharacterLook(outfit: outfit, persona: .drama)
            == CharacterLook(
                persona: "drama", variants: ["body": "person-2", "hair": "bob"],
                colors: ["hair": "#0AABFF", "body": "#000000"]))
}

@Test func whatThisBuildCanNotReadFallsBackToTheDefaults() {
    let look = CharacterLook(persona: "astronaut", variants: ["body": "dog"], colors: ["body": "blue"])

    #expect(Persona(look) == .energetic)
    #expect(Outfit(look) == Outfit(["body": "dog"]))
}
