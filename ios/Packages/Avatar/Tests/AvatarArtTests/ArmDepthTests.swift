import AvatarArt
import AvatarDomain
import Foundation
import Testing

/// Each arm is drawn once, whole, always in front of the body: over the top, the bottom and an
/// accessory's `torso` (a bag at the hip, a bib), under an accessory's `over` (what lies on the
/// shoulders: a sweater, a strap) and under the head, so no arm or sleeve ever crosses the face. An
/// arm never changes depth, so it never jumps from behind the body to in front of it.
@Test func armsAreDrawnOnceInFrontOfTheBodyAndUnderTheHead() throws {
    let figure = try PlaceholderCharacter.figure(wearing: Outfit(["body": "peach", "acc": "halfmoon-tote"]))
    let ids = figure.parts.map(\.id)
    for arm: PartID in ["armL", "armR"] {
        #expect(ids.filter { $0 == arm }.count == 1)
        #expect(try figure.index(arm) > figure.index("torso"))
        #expect(try figure.index(arm) > figure.index("acc"))
        #expect(try figure.index(arm) < figure.index("accOver"))
        #expect(try figure.index(arm) < figure.index("head"))
    }
    #expect(!ids.contains { $0.description.hasSuffix("Back") && $0.description.hasPrefix("arm") })
    // Whatever the angle, both arms show.
    for rotation in [0.0, -45, 45, 160] {
        var pose = figure.restPose
        for arm: PartID in ["armL", "armR"] { pose.parts[try figure.index(arm)].rotation = rotation }
        let placed = figure.layout(pose)
        #expect(try placed[figure.index("armL")].opacity == 1 && placed[figure.index("armR")].opacity == 1)
    }
}

/// A bag's strap lies over the shoulder, so the arm goes under it, while the bag at the hip is under
/// the arm: the tote and the sling draw their straps as `over`, their bags as `torso`; the sweater
/// tied over the shoulders is `over` down to its knot, and its sleeves hanging from it are `torso`.
@Test func strapsLieOverTheArmsAndBagsUnder() throws {
    for (acc, parts) in [
        ("halfmoon-tote", ["acc", "accOver"]), ("moss-sling", ["acc", "accOver"]),
        ("deuce-sweater", ["acc", "accOver"]),
    ] {
        let figure = try PlaceholderCharacter.figure(wearing: Outfit(["body": "peach", "acc": acc]))
        let drawn = figure.parts.filter { ["acc", "accOver"].contains($0.id.description) && !$0.art.isEmpty }
        #expect(drawn.map(\.id.description) == parts, "\(acc)")
    }
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
