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

/// A squadmate's card lists a look head to foot, the prop last, each piece with its rack's store
/// and a gift or prop with none.
@Test func wornListsALookHeadToFootWithItsStores() {
    let choices = EditorChoices(
        species: [], stores: [.init(id: "powder"), .init(id: "warmup")],
        wear: [
            "top": [.init(id: "powder-salmon", store: "powder")],
            "hat": [.init(id: "warmup-cap", store: "warmup")],
        ],
        props: [.init(id: "snowboard")])
    let worn = choices.worn([
        "body": "peach", "prop": "snowboard", "top": "powder-salmon", "hat": "warmup-cap", "acc": "coach-scarf",
    ])
    #expect(
        worn == [
            WornPiece(slot: "hat", id: "warmup-cap", store: "warmup"),
            WornPiece(slot: "top", id: "powder-salmon", store: "powder"),
            WornPiece(slot: "acc", id: "coach-scarf", store: nil),
            WornPiece(slot: "prop", id: "snowboard", store: nil),
        ])
}

/// A look that picks no top or bottom still wears the rig's, and the card lists them.
@Test func wornFillsInTheRigsDefaults() {
    let worn = PlaceholderCharacter.worn(Outfit(["body": "peach", "top": "powder-salmon"]))
    #expect(worn.map(\.id).contains("powder-salmon"))
    #expect(worn.first { $0.slot == "top" }?.store == "powder")
    #expect(worn.contains { $0.slot == "bottom" && $0.id == "warmup-shorts" })
    #expect(!worn.contains { $0.slot == "body" })
}
