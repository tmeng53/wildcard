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

/// A coach's gift hangs on no rack: its slot is the art folder that holds it, as for the shopping
/// bags, which no store lists either.
@Test func aPieceOnNoRackIsWornInTheSlotWhoseFolderHoldsIt() {
    #expect(PlaceholderCharacter.slot(holding: "lap-bib") == Slot("acc"))
    #expect(PlaceholderCharacter.slot(holding: "shopping") == Slot("prop"))
    #expect(PlaceholderCharacter.slot(holding: "gift-no-such-piece") == nil)
}
