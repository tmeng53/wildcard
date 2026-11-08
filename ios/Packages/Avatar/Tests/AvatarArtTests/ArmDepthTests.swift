import AvatarArt
import AvatarDomain
import Foundation
import Testing

/// Each arm is drawn in three places: whole (`armLBack`) before the torso, its forearm
/// (`armLFore`) after the torso and before the head, and its hand (`armL`, which carries the prop)
/// after the head. The forearm and hand show only while the move keys the arm in front (its
/// `front` keys, held like Spine's draw-order keys), never worked out from the angle, so an arm at
/// rest is behind (its sleeve root under the top), a forearm across the chest is over the top, a
/// hand at the face is over the face, and the shoulder and sleeve stay behind the head and chin.
@Test func anArmIsBehindTheBodyUnlessTheMoveBringsItInFront() throws {
    let figure = try PlaceholderCharacter.figure(wearing: Outfit(["body": "peach", "top": "warmup-tee"]))
    func shown(_ part: PartID, front: Double, rotation: Double) throws -> Double {
        var pose = figure.restPose
        for arm: PartID in ["armL", "armR"] {
            pose.parts[try figure.index(arm)].rotation = rotation
            pose.parts[try figure.index(arm)].front = front
        }
        return figure.layout(pose)[try figure.index(part)].opacity
    }
    for side in ["L", "R"] {
        let (hand, fore, back) = (PartID("arm\(side)"), PartID("arm\(side)Fore"), PartID("arm\(side)Back"))
        #expect(try figure.index(back) < figure.index("torso"))
        #expect(try figure.index(fore) > figure.index("torso"))
        #expect(try figure.index(fore) < figure.index("head"))
        #expect(try figure.index(hand) > figure.index("head"))
        #expect(try figure.part(back).art == figure.part(hand).art)
        #expect(try figure.part(fore).art == figure.part(hand).art)
        #expect(try figure.part(back).reach == nil)
        #expect(try figure.part(fore).reach == .forearm)
        #expect(try figure.part(hand).reach == .hand)
        // Whatever the angle, only the key decides.
        for rotation in [0.0, -45, 45, 160] {
            for front in [0.0, 1] {
                #expect(try shown(back, front: front, rotation: rotation) == 1)
                #expect(try shown(fore, front: front, rotation: rotation) == front)
                #expect(try shown(hand, front: front, rotation: rotation) == front)
            }
        }
    }
}

/// The arm's copies move exactly as the arm clips move, bent elbow included.
@Test func theArmsCopiesMoveAsTheArm() throws {
    let figure = try PlaceholderCharacter.figure(wearing: Outfit(["body": "peach"]))
    var pose = figure.restPose
    pose.parts[try figure.index("armL")].rotation = 70
    pose.parts[try figure.index("armL")].bend = 30
    let placed = figure.layout(pose)
    for copy: PartID in ["armLBack", "armLFore"] {
        #expect(try placed[figure.index(copy)].transform == placed[figure.index("armL")].transform)
        #expect(try placed[figure.index(copy)].bend == placed[figure.index("armL")].bend)
    }
}

/// The forearm draws only past a line just above the elbow, the hand only past where the bend
/// ends, and the lines bend with the arm: the shoulder and upper sleeve stay out, and the forearm
/// and hand stay in however far the elbow folds.
@Test func eachCopyDrawsOnlyItsReach() throws {
    let figure = try PlaceholderCharacter.figure(wearing: Outfit(["body": "peach"]))
    let arm = try figure.part("armL")
    let elbow = try #require(arm.elbow)
    func inside(_ part: PartID, _ point: Point, bend: Double) throws -> Bool {
        var pose = figure.restPose
        pose.parts[try figure.index("armL")].bend = bend
        let clip = try #require(figure.layout(pose)[figure.index(part)].clip)
        return winding(clip, point) != 0
    }
    let shoulder = arm.pivot
    let upper = Point(x: shoulder.x * 0.8 + elbow.point.x * 0.2, y: shoulder.y * 0.8 + elbow.point.y * 0.2)
    // The furthest a move folds an arm (gloves) brings the hand back to the shoulder.
    for bend in [0.0, 60, -110, 150] {
        let moved = Bend(shoulder: shoulder, elbow: elbow, degrees: bend)
        for part: PartID in ["armLFore", "armL"] {
            if abs(bend) < 150 {
                #expect(try !inside(part, shoulder, bend: bend))
                #expect(try !inside(part, upper, bend: bend))
            }
            #expect(try inside(part, moved.apply(to: elbow.hand), bend: bend))
        }
        #expect(try inside("armLFore", elbow.point, bend: bend))
        #expect(try !inside("armL", elbow.point, bend: bend))
    }
    #expect(try figure.layout(figure.restPose)[figure.index("armLBack")].clip == nil)
}

/// How many times a polygon winds around a point, 0 outside: clips fill by the nonzero rule.
private func winding(_ polygon: [Point], _ point: Point) -> Int {
    var turns = 0
    for (index, from) in polygon.enumerated() {
        let onto = polygon[(index + 1) % polygon.count]
        let side = (onto.x - from.x) * (point.y - from.y) - (point.x - from.x) * (onto.y - from.y)
        if from.y <= point.y, onto.y > point.y, side > 0 { turns += 1 }
        if from.y > point.y, onto.y <= point.y, side < 0 { turns -= 1 }
    }
    return turns
}

/// What an arm holds stays in its hand whether the arm is drawn in front or behind.
@Test func aHiddenFrontArmStillCarriesItsProp() throws {
    let figure = try PlaceholderCharacter.figure(wearing: Outfit(["body": "peach", "prop": "dumbbell"]))
    let placed = figure.layout(figure.restPose)
    #expect(try placed[figure.index("armR")].opacity == 0)
    #expect(try placed[figure.index("propR")].opacity == 1)
}

/// Every move that keys an arm's depth holds it, never easing between front and behind, and a
/// one-shot hands back to idle with its arms behind, as idle has them.
@Test func movesHoldTheirArmDepthAndOneShotsEndBehind() throws {
    let root = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../Sources/AvatarArt/Placeholder")
    let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
    var keyed = 0
    for case let url as URL in files where url.pathExtension == "json" {
        guard let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
            let tracks = json["tracks"] as? [[String: Any]]
        else { continue }
        let name = url.path().replacing(root.path(), with: "")
        for track in tracks where track["channel"] as? String == "front" {
            keyed += 1
            let keys = try #require(track["keys"] as? [[String: Any]])
            #expect(keys.dropFirst().allSatisfy { $0["ease"] as? String == "hold" }, "\(name) eases its depth")
            if json["loops"] as? Bool != true {
                #expect(keys.last?["v"] as? Double == 0, "\(name) ends in front")
            }
        }
    }
    #expect(keyed > 80)
}
