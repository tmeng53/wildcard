import Foundation

extension Figure {
    /// How much a change of an arm's depth would show in `pose`: the canvas area, in square
    /// points, where its forearm (`front`, an arm's front copy, drawn past the elbow) covers a part
    /// drawn between it and its copy behind the body (the torso, what is worn over it, the other
    /// arm). Where it is 0 the two depths look the same, so the arm can change depth unseen.
    /// Measured on a 2-point grid.
    public func depthSwapShows(_ front: Int, in pose: Pose) -> Double {
        guard parts[front].front, let back = parts.firstIndex(where: { $0.twin == front }) else { return 0 }
        let placed = layout(pose)
        guard let area = placed[front].area, area.count > 2 else { return 0 }
        let forearm = parts[front].rings(placed[front])
        guard let reach = Box(forearm.flatMap { $0 }.flatMap { $0 }) else { return 0 }
        let near = (back + 1..<front).filter { placed[$0].opacity > 0.5 }
            .flatMap { parts[$0].rings(placed[$0]) }
            .compactMap { rings in Box(rings.flatMap { $0 }).flatMap(reach.meeting).map { (rings: rings, box: $0) } }
        guard var box = near.first?.box else { return 0 }
        for other in near.dropFirst() {
            (box.minX, box.minY) = (min(box.minX, other.box.minX), min(box.minY, other.box.minY))
            (box.maxX, box.maxY) = (max(box.maxX, other.box.maxX), max(box.maxY, other.box.maxY))
        }
        let step = 2.0
        var covered = 0.0
        for row in stride(from: box.minY, through: box.maxY, by: step) {
            // Where each shape's outline crosses the row: a point is inside where an odd number
            // of them lie to its right.
            let shapes = near.filter { row >= $0.box.minY && row <= $0.box.maxY }.map { crossings($0.rings, at: row) }
            let (arm, cut) = (forearm.map { crossings($0, at: row) }, crossings([area], at: row))
            guard !shapes.isEmpty, !cut.isEmpty, arm.contains(where: { !$0.isEmpty }) else { continue }
            for column in stride(from: box.minX, through: box.maxX, by: step)
            where shapes.contains(where: { inside(column, $0) }) && inside(column, cut)
                && arm.contains(where: { inside(column, $0) })
            {
                covered += step * step
            }
        }
        return covered
    }
}

extension Figure.Part {
    /// Its filled shapes as polygons in canvas coordinates, each a list of closed rings, curves
    /// flattened to 8 segments.
    fileprivate func rings(_ placement: Placement) -> [[[Point]]] {
        art.flatMap(\.shapes).filter { $0.fill != nil && $0.opacity > 0.5 }.map { shape in
            let path = placement.shaped(shape.path)
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
}

/// A box around points, in canvas coordinates.
private struct Box {
    var minX, minY, maxX, maxY: Double

    init?(_ points: [Point]) {
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
            let minY = points.map(\.y).min(), let maxY = points.map(\.y).max()
        else { return nil }
        (self.minX, self.minY, self.maxX, self.maxY) = (minX, minY, maxX, maxY)
    }

    /// Where it and `other` overlap, nil where they don't.
    func meeting(_ other: Box) -> Box? {
        var both = self
        (both.minX, both.minY) = (max(minX, other.minX), max(minY, other.minY))
        (both.maxX, both.maxY) = (min(maxX, other.maxX), min(maxY, other.maxY))
        return both.minX <= both.maxX && both.minY <= both.maxY ? both : nil
    }
}

/// Where the rings' edges cross the row at `row`.
private func crossings(_ rings: [[Point]], at row: Double) -> [Double] {
    var found: [Double] = []
    for ring in rings {
        for (start, end) in zip(ring, ring.dropFirst() + [ring[0]]) where (start.y > row) != (end.y > row) {
            found.append(start.x + (row - start.y) / (end.y - start.y) * (end.x - start.x))
        }
    }
    return found
}

/// Even-odd: whether `column` on a row is inside the shape that crosses it at `crossings`.
private func inside(_ column: Double, _ crossings: [Double]) -> Bool {
    !crossings.filter { $0 > column }.count.isMultiple(of: 2)
}
