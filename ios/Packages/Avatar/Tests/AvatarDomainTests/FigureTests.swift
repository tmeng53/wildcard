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

/// A twin moves as the part it names, so that part must exist, have the same parent and not be a
/// twin itself.
@Test func aTwinMustNameAnUntwinnedPartWithTheSameParent() throws {
    func twinned(_ twin: PartID, parent: PartID? = "body") -> Rig {
        var twinned = rig
        twinned.parts.append(Rig.Part(id: "armBack", parent: parent, pivot: Point(x: 60, y: 40), twin: twin))
        return twinned
    }
    #expect(throws: Never.self) { try Figure(rig: twinned("arm"), outfit: Outfit([:]), art: art) }
    for bad in [twinned("leg"), twinned("arm", parent: nil), twinned("armBack")] {
        #expect(throws: AvatarError.self) { try Figure(rig: bad, outfit: Outfit([:]), art: art) }
    }
}

/// An arm's front copy (the part a twin names) shows only while its `front` is 1, not at 0 (its
/// rest); the copy behind the body and every other part ignore `front`.
@Test func frontShowsOnlyTheArmsFrontCopy() throws {
    var twinned = rig
    twinned.parts.insert(Rig.Part(id: "armBack", parent: "body", pivot: Point(x: 60, y: 40), twin: "arm"), at: 1)
    let figure = try Figure(rig: twinned, outfit: Outfit([:]), art: art)
    let (body, arm) = (0, 2)
    func shown(front: Double) -> [Double] {
        var pose = figure.restPose
        pose.parts[arm].front = front
        pose.parts[body].front = front
        return figure.layout(pose).map(\.opacity)
    }
    #expect(shown(front: 0) == [1, 1, 0])
    #expect(shown(front: 0.4) == [1, 1, 0])
    #expect(shown(front: 1) == [1, 1, 1])
}

/// An arm's front copy is drawn only past the elbow, so only the forearm comes in front of the body
/// and the shoulder stays behind it: a swap of depth shows only where the forearm crosses the body.
/// The area turns with the bend; the copy behind the body is drawn whole.
@Test func onlyTheForearmComesInFront() throws {
    var twinned = rig
    twinned.parts[1].elbow = Rig.Elbow(point: Point(x: 60, y: 60), hand: Point(x: 60, y: 80))
    twinned.parts.insert(Rig.Part(id: "armBack", parent: "body", pivot: Point(x: 60, y: 40), twin: "arm"), at: 1)
    let figure = try Figure(rig: twinned, outfit: Outfit([:]), art: art)
    func inside(_ point: Point, _ area: [Point]) -> Bool {
        // Convex: the point is on the same side of every edge.
        let sides = area.indices.map { index -> Double in
            let (start, end) = (area[index], area[(index + 1) % area.count])
            return (end.x - start.x) * (point.y - start.y) - (end.y - start.y) * (point.x - start.x)
        }
        return sides.allSatisfy { $0 > 0 } || sides.allSatisfy { $0 < 0 }
    }
    var pose = figure.restPose
    pose.parts[2].front = 1
    let rest = figure.layout(pose)
    #expect(rest[1].area == nil)
    let area = try #require(rest[2].area)
    #expect(inside(Point(x: 60, y: 80), area))
    #expect(inside(Point(x: 60, y: 61), area))
    #expect(!inside(Point(x: 60, y: 59), area))
    #expect(!inside(Point(x: 60, y: 40), area))
    // Bent 90° clockwise, the forearm points left from the elbow, and so does the area.
    pose.parts[2].bend = 90
    let bent = try #require(figure.layout(pose)[2].area)
    #expect(inside(Point(x: 40, y: 60), bent))
    #expect(!inside(Point(x: 70, y: 80), bent))
}
