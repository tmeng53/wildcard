import AvatarArt
import AvatarDomain
import Testing

/// An arm is drawn behind the body and head while it hangs, swings or rises out to the side, so a
/// sleeve's root stays behind the top and a raised arm behind the cheek, and in front once it comes
/// across the chest or up over the head, so hands at the chest or face stay in front. `armLBack` and `armRBack` are the
/// arms again, before the torso, moving as the arms do.
@Test func anArmIsBehindTheBodyUntilItComesAcrossTheChest() throws {
    let figure = try PlaceholderCharacter.figure(wearing: Outfit(["body": "peach", "top": "warmup-tee"]))
    func shown(_ part: PartID, armL: Double = 0, armR: Double = 0) throws -> Double {
        var pose = figure.restPose
        pose.parts[try figure.index("armL")].rotation = armL
        pose.parts[try figure.index("armR")].rotation = armR
        return figure.layout(pose)[try figure.index(part)].opacity
    }
    // armL turns in with negative degrees, armR with positive ones.
    for (front, back, inward): (PartID, PartID, Double) in [("armL", "armLBack", -1), ("armR", "armRBack", 1)] {
        #expect(try figure.index(back) < figure.index("torso"))
        #expect(try figure.index(front) > figure.index("head"))
        #expect(try figure.part(back).art == figure.part(front).art)
        for degrees in [0.0, -15, 15, 120] {
            let rotation = degrees * inward
            #expect(try shown(back, armL: rotation, armR: rotation) == (degrees < 20 ? 1 : 0), "\(back) \(degrees)")
        }
        for degrees in [0.0, 10, 60, 95] {
            let rotation = degrees * -inward
            #expect(try shown(front, armL: rotation, armR: rotation) == 0, "\(front) out \(degrees)")
            #expect(try shown(back, armL: rotation, armR: rotation) == 1, "\(back) out \(degrees)")
        }
        #expect(try shown(front, armL: 44 * inward, armR: 44 * inward) == 1)
        for degrees in [100.0, 150] {
            let rotation = degrees * -inward
            #expect(try shown(front, armL: rotation, armR: rotation) == 1, "\(front) over the head \(degrees)")
            #expect(try shown(back, armL: rotation, armR: rotation) == 0, "\(back) over the head \(degrees)")
        }
    }
}

/// The back arm moves exactly as the arm clips move, bent elbow included.
@Test func theBackArmMovesAsTheArm() throws {
    let figure = try PlaceholderCharacter.figure(wearing: Outfit(["body": "peach"]))
    var pose = figure.restPose
    pose.parts[try figure.index("armL")].rotation = 70
    pose.parts[try figure.index("armL")].bend = 30
    let placed = figure.layout(pose)
    #expect(try placed[figure.index("armLBack")].transform == placed[figure.index("armL")].transform)
    #expect(try placed[figure.index("armLBack")].bend == placed[figure.index("armL")].bend)
}

/// What an arm holds stays in its hand whether the arm is drawn in front or behind.
@Test func aHiddenFrontArmStillCarriesItsProp() throws {
    let figure = try PlaceholderCharacter.figure(wearing: Outfit(["body": "peach", "prop": "dumbbell"]))
    let placed = figure.layout(figure.restPose)
    #expect(try placed[figure.index("armR")].opacity == 0)
    #expect(try placed[figure.index("propR")].opacity == 1)
}
