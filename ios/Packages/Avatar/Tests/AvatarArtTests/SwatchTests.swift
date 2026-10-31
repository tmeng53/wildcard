import AvatarArt
import AvatarDomain
import Testing

private let recolorable: [Slot] = ["body", "hair", "eyes", "brows"] + clothes
private let clothes: [Slot] = ["top", "bottom", "shoes", "hat", "acc"]

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
        if clothes.contains(slot) {
            let onTheRacks = (try PlaceholderCharacter.editorChoices().wear[slot] ?? []).contains { $0.id == variant }
            #expect(swatches.count == (onTheRacks ? 5 : 0), "\(slot) \(variant) has \(swatches.count) swatches")
        } else {
            #expect((6...8).contains(swatches.count), "\(slot) \(variant) has \(swatches.count) swatches")
        }
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

/// Props, mouths, cheeks and glasses keep their art's colors, and so do clothes whose colors are
/// the point; legs keep the shoes' colors when the skin changes.
@Test func propsAndSignatureClothesKeepTheirColors() throws {
    #expect(PlaceholderCharacter.swatches(for: "hat", wearing: "nolook-backcap").isEmpty)
    #expect(PlaceholderCharacter.swatches(for: "shoes", wearing: "lap-runner").isEmpty)
    for (slot, variant) in [("mouth", "grin"), ("cheeks", "rosy"), ("glasses", "round")] {
        #expect(PlaceholderCharacter.swatches(for: Slot(slot), wearing: variant).isEmpty)
    }
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
        ("body", "peach"), ("body", "cat"), ("body", "bear"), ("hair", "bob"), ("top", "warmup-tee"),
        ("bottom", "warmup-shorts"), ("shoes", "warmup-canvas"), ("hat", "warmup-headband"), ("acc", "warmup-towel"),
        ("eyes", "round"), ("brows", "soft"),
    ].map { PlaceholderCharacter.swatches(for: Slot($0.0), wearing: $0.1).count }
    #expect(counts == [7, 6, 6, 7, 5, 5, 5, 5, 5, 6, 7])
    let furs = [("body", "golden"), ("body", "rabbit"), ("body", "lop"), ("hair", "curls")]
        .map { PlaceholderCharacter.swatches(for: Slot($0.0), wearing: $0.1).count }
    #expect(furs == [6, 6, 6, 7])
    #expect(PlaceholderCharacter.swatches(for: "top", wearing: "cape").isEmpty)
}

/// Skin, fur, hair and eyes come from the design system's palette, and clothes from their own
/// colors after the art's, in the order the editor shows them.
@Test func swatchesUseThePalette() {
    #expect(PlaceholderCharacter.swatches(for: "body", wearing: "peach").first == RGBAColor(hex: "#F9DCC4"))
    #expect(PlaceholderCharacter.swatches(for: "hair", wearing: "buzz").last == RGBAColor(hex: "#C4C2CA"))
    #expect(
        PlaceholderCharacter.swatches(for: "top", wearing: "warmup-tee")
            == ["#1F2128", "#2D5BA0", "#278C5E", "#9062DE", "#E65345"].compactMap(RGBAColor.init(hex:)))
    #expect(
        PlaceholderCharacter.swatches(for: "bottom", wearing: "warmup-shorts").first == RGBAColor(hex: "#6B7080"))
    #expect(PlaceholderCharacter.swatches(for: "eyes", wearing: "happy")[3] == RGBAColor(hex: "#4A6FA5"))
    #expect(
        PlaceholderCharacter.swatches(for: "brows", wearing: "bold")
            == PlaceholderCharacter.swatches(for: "hair", wearing: "bob"))
}
