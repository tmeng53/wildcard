import AvatarArt
import AvatarDomain
import Testing

private let recolorable: [Slot] = ["body", "hair", "top", "bottom"]

/// Every look can wear every swatch of every slot it can recolor, and the swatch shows up in
/// its art, so a missing or mistyped `tones.json` fails here.
@Test(arguments: wardrobe)
func everySwatchApplies(outfit: Outfit) throws {
    for slot in recolorable {
        guard let variant = outfit.variants[slot] else { continue }
        let swatches = PlaceholderCharacter.swatches(for: slot, wearing: variant)
        if slot == "body" && fixedCoats.contains(variant) {
            #expect(swatches.isEmpty, "\(variant) keeps its coat's colors")
            continue
        }
        #expect((6...8).contains(swatches.count), "\(slot) \(variant) has \(swatches.count) swatches")
        for swatch in swatches {
            var colored = outfit
            colored.colors[slot] = swatch
            let figure = try PlaceholderCharacter.figure(wearing: colored)
            let colors = figure.parts.flatMap(\.art).flatMap(\.shapes).flatMap { [$0.fill, $0.stroke?.color] }
                .compactMap { $0 }
            #expect(
                colors.contains { ($0.red, $0.green, $0.blue) == (swatch.red, swatch.green, swatch.blue) },
                "\(slot) \(variant) in \(swatch) never paints it")
        }
    }
}

/// Hats and props keep their art's colors; so do the shoes, drawn with the body.
@Test func hatsPropsAndShoesKeepTheirColors() throws {
    #expect(PlaceholderCharacter.swatches(for: "hat", wearing: "cap").isEmpty)
    #expect(PlaceholderCharacter.swatches(for: "prop", wearing: "racket").isEmpty)
    var lifter = PlaceholderCharacter.lifter
    lifter.colors["body"] = RGBAColor(hex: "#5E3B27")
    let figure = try PlaceholderCharacter.figure(wearing: lifter)
    let legs = figure.parts.filter { ["legL", "legR"].contains($0.id.rawValue) }.flatMap(\.art).flatMap(\.shapes)
    #expect(legs.contains { $0.fill == RGBAColor(hex: "#F4F6FA") })
    // The legs are drawn as thick skin-colored strokes.
    #expect(legs.contains { $0.stroke?.color == RGBAColor(hex: "#5E3B27") })
}

/// Each part offers its full list, and a variant without `tones.json` offers none.
@Test func swatchCounts() {
    let counts = [
        ("body", "peach"), ("body", "tan"), ("body", "cat"), ("body", "bear"), ("hair", "bob"), ("top", "tee"),
        ("bottom", "shorts"),
    ].map { PlaceholderCharacter.swatches(for: Slot($0.0), wearing: $0.1).count }
    #expect(counts == [7, 7, 6, 6, 7, 8, 8])
    let furs = [("body", "golden"), ("body", "rabbit"), ("body", "lop"), ("hair", "curls")]
        .map { PlaceholderCharacter.swatches(for: Slot($0.0), wearing: $0.1).count }
    #expect(furs == [6, 6, 6, 7])
    #expect(PlaceholderCharacter.swatches(for: "top", wearing: "cape").isEmpty)
}

/// Every swatch comes from the design system's palette, in the order the editor shows them.
@Test func swatchesUseThePalette() {
    #expect(PlaceholderCharacter.swatches(for: "body", wearing: "peach").first == RGBAColor(hex: "#F9DCC4"))
    #expect(PlaceholderCharacter.swatches(for: "hair", wearing: "buzz").last == RGBAColor(hex: "#C4C2CA"))
    #expect(
        PlaceholderCharacter.swatches(for: "top", wearing: "tee").first == RGBAColor(hex: "#2D5BA0"))
    #expect(
        PlaceholderCharacter.swatches(for: "bottom", wearing: "shorts").first == RGBAColor(hex: "#1F2128"))
}
