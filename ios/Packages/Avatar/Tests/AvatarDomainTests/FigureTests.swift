import AvatarDomain
import Foundation
import Testing

@Test func childrenFollowTheirParent() throws {
    let figure = try figure()
    var pose = figure.restPose
    // Arm swings 90° clockwise at the shoulder: the hand points left, from (60, 80) to (20, 40).
    pose.parts[1].rotation = 90
    #expect(rounded(figure.layout(pose)[1].transform.apply(to: Point(x: 60, y: 80))) == Point(x: 20, y: 40))
    // Body hops 10 up: the arm goes with it.
    pose.parts[0].y = -10
    #expect(rounded(figure.layout(pose)[1].transform.apply(to: Point(x: 60, y: 80))) == Point(x: 20, y: 30))
    // Body squashes to half height from its feet at y 80: the shoulder drops to y 60.
    pose = figure.restPose
    pose.parts[0].scaleY = 0.5
    #expect(rounded(figure.layout(pose)[1].transform.apply(to: Point(x: 60, y: 40))) == Point(x: 60, y: 60))
}

@Test func opacityMultipliesDownTheParts() throws {
    let figure = try figure()
    var pose = figure.restPose
    pose.parts[0].opacity = 0.5
    pose.parts[1].opacity = 0.5
    #expect(figure.layout(pose).map(\.opacity) == [0.5, 0.25])
}

@Test func outfitsSwapTheArtASlotDraws() throws {
    #expect(try figure().parts[1].art.count == 1)
    let dressed = try figure(Outfit(["top": "tee"]))
    #expect(dressed.parts[1].art.count == 2)
    #expect(dressed.parts[1].art[1].shapes[0].stroke?.width == 6)
}

/// A slot the outfit leaves out wears the rig's default; picking another variant, or
/// coloring the default, works as for any slot.
@Test func outfitsFallBackToTheRigsDefaults() throws {
    var dressed = rig
    dressed.defaults = ["top": "tee"]
    let files = Files(files: art.files.merging(["top/vest/arm.svg": sleeve, "top/tee/tones.json": teeTones]) { $1 })
    #expect(try Figure(rig: dressed, outfit: Outfit([:]), art: files).parts[1].art.count == 2)
    let vest = try Figure(rig: dressed, outfit: Outfit(["top": "vest"]), art: files)
    #expect(vest.parts[1].art.count == 2)
    let red = try #require(RGBAColor(hex: "#E65345"))
    let colored = try Figure(rig: dressed, outfit: Outfit([:], colors: ["top": red]), art: files)
    #expect(colored.parts[1].art[1].shapes[0].stroke?.color == red)
    #expect(throws: AvatarError.unknownVariant(slot: "top", variant: "cape")) {
        try Figure(rig: dressed, outfit: Outfit(["top": "cape"]), art: files)
    }
}

private let teeTones = ##"{ "version": 1, "base": "#2D5BA0", "shades": [] }"##

@Test func posesFromAClipLoopOrHold() throws {
    let figure = try figure()
    let wave = try figure.bind(clip("wave", duration: 2, loops: true, [track("arm", .rotation, [(0, 0), (2, 40)])]))
    #expect(figure.pose(wave, at: 1).parts[1].rotation == 20)
    #expect(figure.pose(wave, at: 3).parts[1].rotation == 20)
    #expect(figure.pose(wave, at: 1).parts[0] == PartPose())
    let once = try figure.bind(clip("once", duration: 2, loops: false, [track("arm", .rotation, [(0, 0), (2, 40)])]))
    #expect(figure.pose(once, at: 3).parts[1].rotation == 40)
}

@Test func rejectsRigsAndOutfitsThatDontFit() throws {
    var looped = rig
    looped.parts[0].parent = "arm"
    #expect(throws: AvatarError.parentCycle("body")) { try Figure(rig: looped, outfit: Outfit([:]), art: art) }

    var orphan = rig
    orphan.parts[1].parent = "torso"
    #expect(throws: AvatarError.unknownParent(part: "arm", parent: "torso")) {
        try Figure(rig: orphan, outfit: Outfit([:]), art: art)
    }

    var twin = rig
    twin.parts[1].id = "body"
    #expect(throws: AvatarError.duplicatePart("body")) { try Figure(rig: twin, outfit: Outfit([:]), art: art) }

    #expect(throws: AvatarError.missingArt("base/arm.svg")) {
        try Figure(rig: rig, outfit: Outfit([:]), art: Files(files: ["base/body.svg": square]))
    }
    #expect(throws: AvatarError.unknownVariant(slot: "top", variant: "cape")) { try figure(Outfit(["top": "cape"])) }

    let wide = Files(files: art.files.merging(["base/body.svg": #"<svg viewBox="0 0 200 100"/>"#]) { $1 })
    #expect(throws: AvatarError.canvasMismatch(art: "base/body.svg")) {
        try Figure(rig: rig, outfit: Outfit([:]), art: wide)
    }

    let built = try figure()
    #expect(throws: AvatarError.unknownPart(clip: "kick", part: "leg")) {
        try built.bind(clip("kick", duration: 1, loops: false, [track("leg", .rotation, [(0, 0)])]))
    }
}

@Test func readsRigJSON() throws {
    let rig = try Rig.decode(
        Data(
            #"""
            { "version": 1, "canvas": { "width": 100, "height": 100 }, "defaults": { "top": "tee" }, "parts": [
              { "id": "body", "pivot": [50, 80], "layers": [{ "art": "body" }] },
              { "id": "mouth", "parent": "body", "pivot": [50, 50], "opacity": 0 } ] }
            """#.utf8))
    #expect(rig.parts.map(\.id) == ["body", "mouth"])
    #expect(rig.defaults == ["top": "tee"])
    #expect(rig.parts[1] == Rig.Part(id: "mouth", parent: "body", pivot: Point(x: 50, y: 50), opacity: 0))
    #expect(throws: AvatarError.malformedJSON(".parts[0].pivot[2]: expected [x, y]")) {
        try Rig.decode(
            Data(
                #"{ "version": 1, "canvas": { "width": 1, "height": 1 }, "parts": [{ "id": "a", "pivot": [1, 2, 3] }] }"#
                    .utf8))
    }
    #expect(throws: AvatarError.malformedJSON(".parts[0]: unknown key \"parnet\"")) {
        try Rig.decode(
            Data(
                #"{ "version": 1, "canvas": { "width": 1, "height": 1 }, "parts": [{ "id": "a", "parnet": "b", "pivot": [1, 2] }] }"#
                    .utf8))
    }
}
