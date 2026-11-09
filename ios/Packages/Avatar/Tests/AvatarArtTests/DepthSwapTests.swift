import AvatarArt
import AvatarDomain
import Foundation
import Testing

/// Every change of an arm's depth happens while its forearm is clear of the body, so it can't be
/// seen: where the forearm (the only part drawn in front, `Figure.forearm`) covers the torso, what
/// is worn over it or the other arm, front and behind look different, and a swap there jumps
/// however it is timed. Every move and clip is played as the app plays it (`Performance`), on
/// each species' body, over the persona's idle with that species' moves: from two moments of the
/// idle, blending in, through to the blend back to idle (a loop is ended by the next `play`). At
/// every frame where an arm changes depth, and the frame before, the forearm may overlap what
/// lies between its two copies by at most 16 square points: a sliver along an outline, where the
/// two drawings already agree.
@Test(arguments: ["cat", "bear"])
func everyArmDepthSwapHappensClearOfTheBody(body: String) throws {
    let root = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../Sources/AvatarArt/Placeholder")
    let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
    var swaps = 0
    for case let url as URL in files where url.pathExtension == "json" {
        let name = url.path().replacing(root.path(), with: "")
        guard ["/moves/", "/clips/"].contains(where: name.hasPrefix),
            let clip = try? Clip.decode(Data(contentsOf: url))
        else { continue }
        let file = url.deletingPathExtension().lastPathComponent
        // A persona's own clips, reactions and meals play only for it; the rest for any.
        let own = Persona.allCases.filter { name.contains("/\($0.rawValue)/") || file.hasSuffix("-\($0.rawValue)") }
        // Clips, meals and the entrance play as drawn; every other move at the persona's tempo.
        let asDrawn =
            name.hasPrefix("/clips/") || name.contains("/checkins/") && !name.contains("doze")
            || file == "entrance"
        var look: [Slot: String] = ["body": body, "top": "warmup-tee", "bottom": "warmup-shorts"]
        // A prop's move is played holding it.
        look["prop"] = name.contains("/props/") ? file : nil
        let outfit = Outfit(look)
        let figure = try PlaceholderCharacter.figure(wearing: outfit)
        for persona in own.isEmpty ? Persona.allCases : own {
            let idle = try figure.bind(
                PlaceholderCharacter.clip("idle", persona: persona, species: PlaceholderCharacter.species(of: outfit)))
            let move = try figure.bind(asDrawn ? clip : clip.atTempo(persona.accentTempo))
            for start in [0.5, 2.9] {
                var performance = Performance(figure: figure, idle: idle)
                performance.play(move, at: start)
                let end = start + move.clip.duration * (move.clip.loops ? 1.5 : 1)
                if move.clip.loops { performance.play(idle, at: end) }
                for (frame, pair) in swapsOfDepth(in: performance, figure, through: end + 0.5) {
                    swaps += 1
                    let shown = try max(
                        overlap(of: pair.arm, in: figure, pair.after), overlap(of: pair.arm, in: figure, pair.before))
                    #expect(
                        shown <= 16,
                        "\(name) as \(persona) on \(body) from \(start)s swaps \(pair.arm) at frame \(frame) over \(shown) pt²"
                    )
                }
            }
        }
    }
    #expect(swaps > 200)
}

/// No idle, with any species' moves on top, holds a forearm over the body, so a move can bring an
/// arm in front, or hand it back behind, right as it blends from or back to idle.
@Test(arguments: ["peach", "cat", "corgi", "lop", "bear"])
func noIdleHoldsAnArmOverTheBody(body: String) throws {
    let outfit = Outfit(["body": body, "top": "warmup-tee", "bottom": "warmup-shorts"])
    let figure = try PlaceholderCharacter.figure(wearing: outfit)
    for persona in Persona.allCases {
        let idle = try figure.bind(
            PlaceholderCharacter.clip("idle", persona: persona, species: PlaceholderCharacter.species(of: outfit)))
        for frame in 0...Int(idle.clip.duration / persona.accentTempo * 30) {
            let pose = figure.pose(idle, at: Double(frame) / 30)
            for arm: PartID in ["armL", "armR"] {
                let shown = try overlap(of: arm, in: figure, pose)
                #expect(
                    shown <= 4,
                    "\(persona)'s idle on \(body) holds \(arm) over the body at frame \(frame): \(shown) pt²")
            }
        }
    }
}

/// Each frame, at 60 a second, where an arm's front copy shows or hides, with the poses either
/// side of it.
private func swapsOfDepth(in performance: Performance, _ figure: Figure, through end: Double)
    -> [(frame: Int, pair: (arm: PartID, before: Pose, after: Pose))]
{
    var found: [(frame: Int, pair: (arm: PartID, before: Pose, after: Pose))] = []
    var before = performance.pose(at: 0)
    for frame in 1...Int((end * 60).rounded(.up)) {
        let pose = performance.pose(at: Double(frame) / 60)
        for (index, part) in figure.parts.enumerated()
        where part.front && (pose.parts[index].front >= 0.5) != (before.parts[index].front >= 0.5) {
            found.append((frame, (part.id, before, pose)))
        }
        before = pose
    }
    return found
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
