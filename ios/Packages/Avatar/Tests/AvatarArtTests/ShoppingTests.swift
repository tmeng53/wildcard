import AvatarArt
import AvatarDomain
import AvatarLooks
import Testing

/// Every species carries the bags: one look each, as the lineup and the editor's bodies give.
private let shoppers: [Outfit] =
    Looks.squad
    + ["peach", "cat", "shiba", "collie", "rabbit", "lop", "bear"].map {
        Outfit(["body": $0, "top": "warmup-tee", "bottom": "warmup-shorts"])
    }

/// The bags are 商店街's, never a pick in the editor.
@Test func theEditorNeverOffersTheBags() throws {
    #expect(!PlaceholderCharacter.variants(for: "prop").contains(PlaceholderCharacter.shoppingBags))
    #expect(try !PlaceholderCharacter.editorChoices().props.map(\.id).contains(PlaceholderCharacter.shoppingBags))
    var look = PlaceholderCharacter.lifter
    look.colors["prop"] = RGBAColor(red: 230, green: 83, blue: 69)
    let shopper = PlaceholderCharacter.shopping(look)
    #expect(shopper.variants["prop"] == "shopping")
    #expect(shopper.colors["prop"] == nil)
    #expect(try PlaceholderCharacter.drawable(shopper).variants["prop"] == "shopping")
}

/// The walk loops and the stop plays once; both turn the bags themselves, start from the same
/// frame (so the stop takes over as a step ends) and stay on the canvas; the stop ends at rest.
@Test func theShopperWalksAndStops() throws {
    let walk = try PlaceholderCharacter.shoppingWalk()
    let spot = try PlaceholderCharacter.shoppingSpot()
    #expect(walk.loops)
    #expect(!spot.loops)
    #expect(walk.holds == "shopping")
    #expect(spot.holds == "shopping")
    for look in shoppers {
        let figure = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.shopping(look))
        let (walking, spotting) = (try figure.bind(walk), try figure.bind(spot))
        #expect(nearlyEqual(figure.pose(walking, at: walk.duration), figure.pose(walking, at: 0)), "the walk loops")
        expectOnCanvas(figure, walking, for: walk.duration, "shopping walk")
        expectOnCanvas(figure, spotting, for: spot.duration, "shopping spot")
        #expect(
            nearlyEqual(shown(figure.pose(spotting, at: spot.duration)), shown(figure.restPose)), "spot ends at rest")
    }
}

/// The bags hang from the fists: however the arms and body move, each stays within a natural
/// swing of straight down, and the walk keeps them swinging.
@Test func theBagsHangFromTheFists() throws {
    let figure = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.shopping(PlaceholderCharacter.lifter))
    let carriers: [(bag: PartID, arm: PartID)] = [("propL", "armL"), ("propR", "armR")]
    for (clip, most, least) in [
        (try PlaceholderCharacter.shoppingWalk(), 12.0, 4.0), (try PlaceholderCharacter.shoppingSpot(), 26.0, 8.0),
    ] {
        let bound = try figure.bind(clip)
        for (bag, arm) in carriers {
            var widest = 0.0
            for frame in 0...Int(clip.duration * 100) {
                let pose = figure.pose(bound, at: Double(frame) / 100)
                let turned =
                    pose.parts[try figure.index(bag)].rotation + pose.parts[try figure.index(arm)].rotation
                    + pose.parts[try figure.index(arm)].bend + pose.parts[try figure.index("torso")].rotation
                    + pose.parts[try figure.index("root")].rotation
                widest = max(widest, abs(turned))
            }
            #expect(widest <= most, "\(clip.name) \(bag) swings \(widest)°")
            #expect(widest >= least, "\(clip.name) \(bag) only swings \(widest)°")
        }
    }
}
