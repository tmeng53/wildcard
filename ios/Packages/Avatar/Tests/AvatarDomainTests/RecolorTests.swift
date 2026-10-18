import AvatarDomain
import Foundation
import Testing

private func hex(_ text: String) throws -> RGBAColor {
    try #require(RGBAColor(hex: text))
}

private let tones = ##"{"version": 1, "base": "#2D5BA0", "shades": ["#28467E"]}"##
/// A tee sleeve in its base blue with a darker blue outline, plus a white stripe that isn't
/// one of its tones.
private let toned = ##"""
    <svg viewBox="0 0 100 100">
      <path d="M60 40 L60 50" fill="#2D5BA0" stroke="#28467E" stroke-width="6"/>
      <path d="M58 45 L62 45" stroke="#FFFFFF" stroke-opacity="0.8"/>
    </svg>
    """##

private func recolorable(tones text: String? = tones) -> Files {
    var files = art.files
    files["top/tee/arm.svg"] = toned
    files["top/tee/tones.json"] = text
    return Files(files: files)
}

@Test func readsHexColors() throws {
    #expect(RGBAColor(hex: "#2D5BA0") == RGBAColor(red: 0x2D, green: 0x5B, blue: 0xA0))
    #expect(RGBAColor(hex: "#fa0") == RGBAColor(red: 0xFF, green: 0xAA, blue: 0x00))
    #expect(RGBAColor(hex: "2D5BA0") == nil)
    #expect(RGBAColor(hex: "#2D5BAG") == nil)
    #expect(RGBAColor(hex: "#+D5BA0") == nil)
}

@Test func theBaseBecomesTheTargetAndShadesKeepTheirRelation() throws {
    let (blue, red) = (try hex("#2D5BA0"), try hex("#E65345"))
    #expect(blue.recolored(from: blue, to: red) == red)
    // A darker outline of the blue becomes a darker outline of the red.
    #expect(try hex("#28467E").recolored(from: blue, to: red) == hex("#CE3B24"))
    // Opacity stays the shape's own.
    let faint = RGBAColor(red: 0x2D, green: 0x5B, blue: 0xA0, opacity: 0.5)
    #expect(faint.recolored(from: blue, to: red) == RGBAColor(red: 0xE6, green: 0x53, blue: 0x45, opacity: 0.5))
    // A lighter muzzle on brown fur goes to white when the fur turns polar white.
    #expect(try hex("#D4B39E").recolored(from: hex("#B98563"), to: hex("#F2EFE8")) == hex("#FFFFFF"))
    // A gray base has no saturation to scale: shades take the target's.
    #expect(try hex("#3C3E4F").recolored(from: hex("#4A4F5C"), to: hex("#278C5E")) == hex("#168062"))
}

@Test func aColorRecolorsOnlyTheSlotsTones() throws {
    let figure = try Figure(
        rig: rig, outfit: Outfit(["top": "tee"], colors: ["top": hex("#E65345")]), art: recolorable())
    let sleeve = figure.parts[1].art[1].shapes
    #expect(sleeve[0].fill == (try hex("#E65345")))
    #expect(sleeve[0].stroke?.color == (try hex("#CE3B24")))
    // The stripe and the base art keep their colors.
    #expect(sleeve[1].stroke?.color == RGBAColor(red: 0xFF, green: 0xFF, blue: 0xFF, opacity: 0.8))
    #expect(figure.parts[1].art[0].shapes[0].stroke?.color == (try hex("#000000")))
    // Without a color the art keeps its own.
    let plain = try Figure(rig: rig, outfit: Outfit(["top": "tee"]), art: recolorable())
    #expect(plain.parts[1].art[1].shapes[0].fill == (try hex("#2D5BA0")))
}

@Test func rejectsColorsThatCantApply() throws {
    let red = try hex("#E65345")
    #expect(throws: AvatarError.colorForBareSlot("top")) {
        try Figure(rig: rig, outfit: Outfit([:], colors: ["top": red]), art: recolorable())
    }
    #expect(throws: AvatarError.notRecolorable(slot: "top", variant: "tee")) {
        try Figure(rig: rig, outfit: Outfit(["top": "tee"], colors: ["top": red]), art: recolorable(tones: nil))
    }
    let typo = ##"{"version": 1, "base": "#2D5BA0", "shades": ["#28467F"]}"##
    #expect(throws: AvatarError.unusedTone(slot: "top", variant: "tee", color: try hex("#28467F"))) {
        try Figure(rig: rig, outfit: Outfit(["top": "tee"], colors: ["top": red]), art: recolorable(tones: typo))
    }
}

@Test func tonesJSONIsStrict() throws {
    func decode(_ text: String) throws(AvatarError) -> Tones { try Tones.decode(Data(text.utf8)) }
    #expect(try decode(tones) == Tones(base: hex("#2D5BA0"), shades: [hex("#28467E")]))
    #expect(throws: AvatarError.unsupportedVersion(2)) {
        try decode(##"{"version": 2, "base": "#2D5BA0", "shades": []}"##)
    }
    #expect(throws: AvatarError.malformedJSON(": unknown key \"shade\"")) {
        try decode(##"{"version": 1, "base": "#2D5BA0", "shade": []}"##)
    }
    #expect(throws: AvatarError.malformedJSON(".shades[0]: not a #rrggbb color")) {
        try decode(##"{"version": 1, "base": "#2D5BA0", "shades": ["blue"]}"##)
    }
}
