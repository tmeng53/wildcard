import AvatarDomain
import Foundation
import Testing

/// A body with an arm whose hand is a skin-colored dot, and a prop slot drawn in the arm's hand:
/// a stick, and a fist around it in the rig's skin.
private let hand = ##"""
    <svg viewBox="0 0 100 100"><path d="M60 40 L60 80" fill="none" stroke="#000" stroke-width="4"/>\#
    <circle cx="60" cy="80" r="4" fill="#F5CDAE" stroke="#B89A8B" stroke-width="1"/></svg>
    """##
private let paw = hand.replacingOccurrences(of: "#F5CDAE", with: "#F2A65A")
    .replacingOccurrences(of: "#B89A8B", with: "#B67E4E")
private let stick = ##"<svg viewBox="0 0 100 100"><path d="M60 70 L60 95" stroke="#333" stroke-width="2"/></svg>"##
private let fist = ##"""
    <svg viewBox="0 0 100 100"><circle cx="60" cy="80" r="4" fill="#F5CDAE" stroke="#B89A8B" stroke-width="1"/>\#
    <path d="M57 79 L63 79" fill="none" stroke="#B89A8B" stroke-width="1"/></svg>
    """##

private let heldRig = Rig(
    width: 100, height: 100,
    parts: [
        Rig.Part(id: "body", pivot: Point(x: 50, y: 80), layers: [Rig.Layer(slot: "body", art: "body")]),
        Rig.Part(id: "arm", parent: "body", pivot: Point(x: 60, y: 40), layers: [Rig.Layer(slot: "body", art: "arm")]),
        Rig.Part(id: "prop", parent: "arm", pivot: Point(x: 60, y: 80), layers: [Rig.Layer(slot: "prop", art: "prop")]),
        Rig.Part(
            id: "grip", parent: "prop", pivot: Point(x: 60, y: 80),
            layers: [Rig.Layer(slot: "prop", art: "grip", hand: "arm")]),
    ],
    skin: Rig.Skin(
        fill: RGBAColor(red: 0xF5, green: 0xCD, blue: 0xAE), stroke: RGBAColor(red: 0xB8, green: 0x9A, blue: 0x8B)))

private func held(_ body: String, _ prop: String = "stick", level: String? = nil) throws -> Figure {
    var files = [
        "body/peach/body.svg": square, "body/peach/arm.svg": hand, "body/cat/body.svg": square, "body/cat/arm.svg": paw,
        "prop/\(prop)/prop.svg": stick, "prop/\(prop)/grip.svg": fist,
    ]
    if let level { files["prop/\(prop)/hold.json"] = #"{"version": 1, "level": "\#(level)"}"# }
    return try Figure(rig: heldRig, outfit: Outfit(["body": body, "prop": prop]), art: Files(files: files))
}

/// The fist around a held prop takes the fill and outline of the wearer's own hand.
@Test func aGripTakesTheWearersHand() throws {
    let colors = { (figure: Figure) in
        figure.parts[3].art[0].shapes.flatMap { [$0.fill?.hex, $0.stroke?.color.hex].compactMap { $0 } }
    }
    #expect(colors(try held("peach")) == ["#F5CDAE", "#B89A8B", "#B89A8B"])
    #expect(colors(try held("cat")) == ["#F2A65A", "#B67E4E", "#B67E4E"])
}

@Test func aGripNeedsAHandAndASkin() throws {
    var noSkin = heldRig
    noSkin.skin = nil
    let files = Files(files: ["body/peach/body.svg": square, "body/peach/arm.svg": hand, "prop/stick/grip.svg": fist])
    #expect(throws: AvatarError.noHand("arm")) {
        try Figure(rig: noSkin, outfit: Outfit(["body": "peach", "prop": "stick"]), art: files)
    }
}

/// A prop that keeps level turns back as its arm and the body carrying it turn, in any clip but
/// its own, which turns it as it likes.
@Test func aLevelPropTurnsBackWithItsArm() throws {
    let raise = try clip(
        "cheer", duration: 1, loops: false,
        [track("arm", .rotation, [(0, 0), (1, -90)]), track("body", .rotation, [(0, 0), (1, 10)])])
    let figure = try held("peach", "goggles", level: "arm")
    let prop = 2
    #expect(figure.pose(try figure.bind(raise), at: 1).parts[prop].rotation == 80)
    let own = try Clip(
        name: "goggles", duration: 1, loops: false,
        tracks: [track("arm", .rotation, [(0, 0), (1, -90)]), track("prop", .rotation, [(0, 0), (1, 20)])],
        holds: "goggles")
    #expect(figure.pose(try figure.bind(own), at: 1).parts[prop].rotation == 20)
    // A prop that doesn't keep level turns with the arm.
    let racket = try held("peach", "racket")
    #expect(racket.pose(try racket.bind(raise), at: 1).parts[prop].rotation == 0)
}

@Test func aHoldNamesAnArmTheRigHas() throws {
    #expect(throws: AvatarError.unknownArm(art: "prop/goggles/hold.json", arm: "leg")) {
        try held("peach", "goggles", level: "leg")
    }
}
