import AvatarArt
import AvatarDomain
import Foundation
import Testing

/// Each arm is drawn in two places: whole behind the torso (`armLBack`), and whole in front of the
/// torso and what is worn over it but behind the head (`armL`). The front copy shows only while
/// the move keys the arm in front (its `front` keys, held like Spine's draw-order keys), never
/// worked out from the angle. The head always covers both, so no arm or sleeve ever crosses the
/// face, and an arm at rest is behind, its sleeve root under the top.
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
        let (arm, back) = (PartID("arm\(side)"), PartID("arm\(side)Back"))
        #expect(try figure.index(back) < figure.index("torso"))
        #expect(try figure.index(arm) > figure.index("acc"))
        #expect(try figure.index(arm) < figure.index("head"))
        #expect(try figure.part(back).art == figure.part(arm).art)
        // Whatever the angle, only the key decides.
        for rotation in [0.0, -45, 45, 160] {
            for front in [0.0, 1] {
                #expect(try shown(back, front: front, rotation: rotation) == 1)
                #expect(try shown(arm, front: front, rotation: rotation) == front)
            }
        }
    }
}

/// The copy behind the body moves exactly as the arm clips move, bent elbow included.
@Test func theArmsCopyMovesAsTheArm() throws {
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

/// The head covers the arms, so a hand on the face would vanish behind it: no clip rests a hand
/// deep inside a big (bear's) face, where it neither shows nor reads. A hand by the face sits at
/// its edge, half out.
@Test func noHandRestsOnTheFace() throws {
    let figure = try PlaceholderCharacter.figure(wearing: Outfit(["body": "bear"]))
    // The bear's face, in its head's own coordinates (`art/body/bear/head.svg`).
    let (center, radii) = (Point(x: 120, y: 147.6), (x: 79.2, y: 69.6))
    let root = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../Sources/AvatarArt/Placeholder")
    let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
    var checked = 0
    for case let url as URL in files where url.pathExtension == "json" {
        let name = url.path().replacing(root.path(), with: "")
        guard ["/moves/", "/clips/", "/accents/"].contains(where: url.path().contains),
            let clip = try? Clip.decode(Data(contentsOf: url))
        else { continue }
        let bound = try figure.bind(clip)
        checked += 1
        for step in 0...100 {
            let pose = figure.pose(bound, at: clip.duration * Double(step) / 100)
            let placed = figure.layout(pose)
            let head = placed[try figure.index("head")].transform
            for (arm, held): (PartID, PartID) in [("armL", "propL"), ("armR", "propR")]
            where pose.parts[try figure.index(arm)].opacity > 0.5 {
                let hand = placed[try figure.index(held)].transform.apply(to: try figure.part(held).pivot)
                let local = try #require(inverse(head)).apply(to: hand)
                let reach = ((local.x - center.x) / radii.x, (local.y - center.y) / radii.y)
                let inside = (reach.0 * reach.0 + reach.1 * reach.1).squareRoot()
                #expect(inside >= 0.85, "\(name) rests \(arm)'s hand on the face at step \(step)")
            }
        }
    }
    #expect(checked > 100)
}

/// The transform that undoes `transform`, nil when it squashes the plane flat.
private func inverse(_ transform: Transform) -> Transform? {
    let det = transform.a * transform.d - transform.b * transform.c
    guard det != 0 else { return nil }
    return Transform(
        a: transform.d / det, b: -transform.b / det, c: -transform.c / det, d: transform.a / det,
        tx: (transform.c * transform.ty - transform.d * transform.tx) / det,
        ty: (transform.b * transform.tx - transform.a * transform.ty) / det)
}
