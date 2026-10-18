import AvatarDomain
import Foundation

/// A two-part figure on a 100×100 canvas: a body, and an arm it carries whose pivot is
/// the shoulder at (60, 40) and whose art is a line from there to the hand at (60, 80).
struct Files: ArtSource {
    var files: [String: String]

    func svg(at path: String) -> String? {
        files[path]
    }
}

let square = #"<svg viewBox="0 0 100 100"><rect x="40" y="40" width="20" height="40"/></svg>"#
let arm = ##"<svg viewBox="0 0 100 100"><path d="M60 40 L60 80" stroke="#000" stroke-width="4"/></svg>"##
let sleeve = ##"<svg viewBox="0 0 100 100"><path d="M60 40 L60 50" stroke="#2D5BA0" stroke-width="6"/></svg>"##

let art = Files(files: ["base/body.svg": square, "base/arm.svg": arm, "top/tee/arm.svg": sleeve])

let rig = Rig(
    width: 100, height: 100,
    parts: [
        Rig.Part(id: "body", pivot: Point(x: 50, y: 80), layers: [Rig.Layer(art: "body")]),
        Rig.Part(
            id: "arm", parent: "body", pivot: Point(x: 60, y: 40),
            layers: [Rig.Layer(art: "arm"), Rig.Layer(slot: "top", art: "arm")]),
    ])

func figure(_ outfit: Outfit = Outfit([:])) throws -> Figure {
    try Figure(rig: rig, outfit: outfit, art: art)
}

func clip(_ name: String, duration: Double, loops: Bool, _ tracks: [Clip.Track]) throws -> Clip {
    try Clip(name: name, duration: duration, loops: loops, tracks: tracks)
}

func track(_ part: PartID, _ channel: Channel, _ keys: [(Double, Double)], easing: Easing = .linear) -> Clip.Track {
    Clip.Track(
        part: part, channel: channel,
        keys: keys.map { Clip.Keyframe(time: $0.0, value: $0.1, easing: easing) })
}

/// Rounds away floating-point noise so expectations can be literal.
func rounded(_ point: Point) -> Point {
    Point(x: (point.x * 1000).rounded() / 1000, y: (point.y * 1000).rounded() / 1000)
}
