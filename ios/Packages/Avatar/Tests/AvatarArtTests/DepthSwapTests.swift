import AvatarArt
import AvatarDomain
import Foundation
import Testing

/// Every change of an arm's depth happens while its forearm is clear of the body, so it can't be
/// seen: where the forearm (the only part drawn in front, `Figure.forearm`) covers the torso, what
/// is worn over it or the other arm, front and behind look different, and a swap there jumps
/// however it is timed. Measured as the canvas area, in square points, where the forearm overlaps
/// what lies between its two copies, at the swap and the frame before it.
@Test func everyArmDepthSwapHappensClearOfTheBody() throws {
    let root = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../Sources/AvatarArt/Placeholder")
    let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
    var swaps = 0
    for case let url as URL in files where url.pathExtension == "json" {
        let name = url.path().replacing(root.path(), with: "")
        guard ["/moves/", "/clips/", "/accents/"].contains(where: url.path().contains),
            let clip = try? Clip.decode(Data(contentsOf: url))
        else { continue }
        // A prop's move is played holding it.
        let prop = url.path().contains("/props/") ? url.deletingPathExtension().lastPathComponent : nil
        var look: [Slot: String] = ["body": "cat", "top": "warmup-tee", "bottom": "warmup-shorts"]
        look["prop"] = prop
        let figure = try PlaceholderCharacter.figure(wearing: Outfit(look))
        let bound = try figure.bind(clip)
        for track in clip.tracks where track.channel == .front {
            for (previous, key) in zip(track.keys, track.keys.dropFirst()) where key.value != previous.value {
                swaps += 1
                let shown =
                    try [key.time, key.time - 1.0 / 60].map {
                        try overlap(of: track.part, in: figure, blendedIn(bound, figure, at: max($0, 0)))
                    }.max() ?? 0
                #expect(shown <= 16, "\(name) swaps \(track.part) at \(key.time) over \(shown) pt² of the body")
            }
        }
    }
    #expect(swaps > 200)
}

/// A clip's pose as it plays from rest: crossfading in from idle over its first moments, as
/// `Performance` plays it.
private func blendedIn(_ bound: BoundClip, _ figure: Figure, at time: Double) -> Pose {
    let blend = 0.15
    let fraction = min(time / blend, 1)
    return figure.restPose.blended(to: figure.pose(bound, at: time), amount: fraction * fraction * (3 - 2 * fraction))
}

/// The area where an arm's front copy, drawn past the elbow, covers a part drawn between it and
/// its copy behind the body.
private func overlap(of arm: PartID, in figure: Figure, _ pose: Pose) throws -> Double {
    let front = try figure.index(arm)
    let back = try #require(figure.parts.firstIndex { $0.twin == front })
    let placed = figure.layout(pose)
    let area = try #require(placed[front].area)
    let forearm = polygons(figure.parts[front], placed[front])
    let between = (back + 1..<front).filter { placed[$0].opacity > 0.5 }
        .flatMap { polygons(figure.parts[$0], placed[$0]) }
    guard let box = bounds(forearm) else { return 0 }
    let step = 2.0
    var covered = 0.0
    for row in stride(from: box.min.y, through: box.max.y, by: step) {
        for column in stride(from: box.min.x, through: box.max.x, by: step) {
            let point = Point(x: column, y: row)
            guard inside(point, [area]), forearm.contains(where: { inside(point, $0) }),
                between.contains(where: { inside(point, $0) })
            else { continue }
            covered += step * step
        }
    }
    return covered
}

/// A part's filled shapes as polygons in canvas coordinates, each a list of closed rings.
private func polygons(_ part: Figure.Part, _ placement: Placement) -> [[[Point]]] {
    part.art.flatMap(\.shapes).filter { $0.fill != nil && $0.opacity > 0.5 }.map { shape in
        let path = placement.bend.map { $0.apply(to: shape.path) } ?? shape.path
        var rings: [[Point]] = []
        var ring: [Point] = []
        var pen = Point(x: 0, y: 0)
        for element in path {
            switch element {
            case .move(let point):
                if ring.count > 2 { rings.append(ring) }
                (ring, pen) = ([point], point)
            case .line(let point):
                ring.append(point)
                pen = point
            case .quadCurve(let end, let control):
                ring += (1...8).map { step in
                    let (late, early) = (Double(step) / 8, 1 - Double(step) / 8)
                    return Point(
                        x: early * early * pen.x + 2 * early * late * control.x + late * late * end.x,
                        y: early * early * pen.y + 2 * early * late * control.y + late * late * end.y)
                }
                pen = end
            case .curve(let end, let one, let two):
                ring += (1...8).map { step in
                    let (late, early) = (Double(step) / 8, 1 - Double(step) / 8)
                    let weights = (early * early * early, 3 * early * early * late, 3 * early * late * late)
                    return Point(
                        x: weights.0 * pen.x + weights.1 * one.x + weights.2 * two.x + late * late * late * end.x,
                        y: weights.0 * pen.y + weights.1 * one.y + weights.2 * two.y + late * late * late * end.y)
                }
                pen = end
            case .close:
                if let first = ring.first { pen = first }
            }
        }
        if ring.count > 2 { rings.append(ring) }
        return rings.map { $0.map(placement.transform.apply) }
    }
}

private func bounds(_ shapes: [[[Point]]]) -> (min: Point, max: Point)? {
    let points = shapes.flatMap { $0.flatMap { $0 } }
    guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
        let minY = points.map(\.y).min(), let maxY = points.map(\.y).max()
    else { return nil }
    return (Point(x: minX, y: minY), Point(x: maxX, y: maxY))
}

/// Even-odd: whether `point` is inside the rings.
private func inside(_ point: Point, _ rings: [[Point]]) -> Bool {
    var crossings = false
    for ring in rings {
        for (start, end) in zip(ring, ring.dropFirst() + [ring[0]])
        where (start.y > point.y) != (end.y > point.y)
            && point.x < start.x + (point.y - start.y) / (end.y - start.y) * (end.x - start.x)
        {
            crossings.toggle()
        }
    }
    return crossings
}
