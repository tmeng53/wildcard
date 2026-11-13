import AvatarDomain
import Foundation
import Testing

@Test func aRopeSagsWhileItsEndsAreCloserThanItsLength() {
    // 40 long, its ends 30 apart: sag √(3·30·10/8), the control twice that below the middle.
    let rope = Rope(from: Point(x: 0, y: 0), to: Point(x: 30, y: 0), length: 40)
    #expect(rounded(rope.control) == Point(x: 15, y: 21.213))
    let line: [PathElement] = [.move(Point(x: 1, y: 1)), .line(Point(x: 2, y: 2))]
    #expect(
        rope.apply(to: line)
            == [.move(Point(x: 0, y: 0)), .quadCurve(end: Point(x: 30, y: 0), control: rope.control)])
}

@Test func aRopePulledToItsLengthOrPastItHangsStraight() {
    for reach in [40.0, 55] {
        let rope = Rope(from: Point(x: 0, y: 10), to: Point(x: reach, y: 10), length: 40)
        #expect(rope.control == Point(x: reach / 2, y: 10))
    }
}

/// A fist at (10, 10) on `hand` and a collar at (40, 10) on `dog`, a leash between them 30 long
/// (no slack) drawn as one straight line at rest.
private let leash = ##"<svg viewBox="0 0 100 100"><path d="M10 10 L40 10" stroke="#E65345" stroke-width="2"/></svg>"##
private let leashArt = Files(files: ["base/body.svg": square, "prop/dog/leash.svg": leash])

private func leashRig(parent: PartID? = nil) -> Rig {
    Rig(
        width: 100, height: 100,
        parts: [
            Rig.Part(id: "hand", pivot: Point(x: 10, y: 10), layers: [Rig.Layer(art: "body")]),
            Rig.Part(id: "dog", pivot: Point(x: 40, y: 10)),
            Rig.Part(
                id: "leash", parent: parent, pivot: Point(x: 25, y: 10),
                layers: [Rig.Layer(slot: "prop", art: "leash")],
                rope: Rig.RopeEnds(
                    start: Rig.Anchor(part: "hand", point: Point(x: 10, y: 10)),
                    end: Rig.Anchor(part: "dog", point: Point(x: 40, y: 10)), slack: 0)),
        ])
}

@Test func aRopeFollowsBothEndsAndShowsAsMuchAsTheFainterOne() throws {
    let figure = try Figure(rig: leashRig(), outfit: Outfit(["prop": "dog"]), art: leashArt)
    let rest = figure.layout(figure.restPose)[2]
    #expect(rest.rope?.control == Point(x: 25, y: 10))
    #expect(rest.transform == .identity)

    // The dog runs 10 toward the fist: the leash, 30 long over 20, sags by √(3·20·10/8).
    var pose = figure.restPose
    pose.parts[1].x = -10
    pose.parts[0].opacity = 0.5
    let slack = figure.layout(pose)[2]
    #expect(slack.rope?.start == Point(x: 10, y: 10))
    #expect(slack.rope?.end == Point(x: 30, y: 10))
    #expect(slack.rope.map { rounded($0.control) } == Point(x: 20, y: 27.321))
    #expect(slack.opacity == 0.5)

    pose.parts[1].opacity = 0
    #expect(figure.layout(pose)[2].opacity == 0)
}

@Test func aRopeHasNoParentAndIsDrawnAsStraightLines() {
    #expect(throws: AvatarError.invalidRope(part: "leash", problem: "a rope has no parent or elbow")) {
        try Figure(rig: leashRig(parent: "hand"), outfit: Outfit(["prop": "dog"]), art: leashArt)
    }
    let curved = ##"<svg viewBox="0 0 100 100"><path d="M10 10 Q25 20 40 10" stroke="#000"/></svg>"##
    let art = Files(files: ["base/body.svg": square, "prop/dog/leash.svg": curved])
    #expect(
        throws: AvatarError.invalidRope(part: "leash", problem: "its art must be straight lines, each M x y L x y")
    ) {
        try Figure(rig: leashRig(), outfit: Outfit(["prop": "dog"]), art: art)
    }
}
