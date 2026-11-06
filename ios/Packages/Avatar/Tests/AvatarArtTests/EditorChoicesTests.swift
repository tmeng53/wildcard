import AvatarArt
import AvatarDomain
import Testing

@Test func aPieceIsWornInItsRacksSlotAndAPropInTheHand() throws {
    let choices = try PlaceholderCharacter.editorChoices()
    #expect(choices.slot(of: "lap-bib") == Slot("acc"))
    #expect(choices.slot(of: "warmup-beanie") == Slot("hat"))
    #expect(choices.slot(of: "racket") == Slot("prop"))
    #expect(choices.slot(of: "no-such-piece") == nil)
}
