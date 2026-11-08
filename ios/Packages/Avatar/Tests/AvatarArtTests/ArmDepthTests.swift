import AvatarArt
import AvatarDomain
import Foundation
import Testing

/// Each arm is drawn twice: `armLBack` and `armRBack` before the torso, the arms themselves after
/// the head. Which one shows is part of the move (its `front` keys, held like Spine's draw-order
/// keys), never worked out from the angle, so an arm at rest is behind (its sleeve root under the
/// top) and a move brings it in front only where its hand is at the face, over the head or across
/// the chest.
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
    for (front, back): (PartID, PartID) in [("armL", "armLBack"), ("armR", "armRBack")] {
        #expect(try figure.index(back) < figure.index("torso"))
        #expect(try figure.index(front) > figure.index("head"))
        #expect(try figure.part(back).art == figure.part(front).art)
        // Whatever the angle, only the key decides.
        for rotation in [0.0, -45, 45, 160] {
            #expect(try shown(front, front: 0, rotation: rotation) == 0)
            #expect(try shown(back, front: 0, rotation: rotation) == 1)
            #expect(try shown(front, front: 1, rotation: rotation) == 1)
            #expect(try shown(back, front: 1, rotation: rotation) == 0)
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
