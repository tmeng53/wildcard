import AvatarArt
import AvatarDomain
import Testing

/// A shop's rack shows a piece on its own: only its own art, where the rig puts it.
@Test(arguments: ["top", "bottom", "shoes", "hat", "acc"] as [Slot])
func aPieceOnItsOwnDrawsNothingElse(slot: Slot) throws {
    var look = PlaceholderCharacter.lifter
    look.variants["hat"] = "warmup-cap"
    look.variants["acc"] = "warmup-waistbag"
    let figure = try PlaceholderCharacter.figure(wearing: look)
    let piece = figure.wearing(only: slot)
    #expect(piece.parts.flatMap(\.slots).allSatisfy { $0 == slot })
    #expect(piece.parts.flatMap(\.art).count == figure.parts.flatMap(\.slots).filter { $0 == slot }.count)
    #expect(piece.parts.map(\.id) == figure.parts.map(\.id))
}

/// The body's arm starts in a round shoulder that stays put while the arm turns, so a sleeve
/// covers that whole circle: with the arms up, a sleeve that didn't would show the shoulder
/// under it as a hole of skin.
@Test(arguments: PlaceholderCharacter.variants(for: "top"))
func everySleeveCoversTheShoulder(top: String) throws {
    var look = PlaceholderCharacter.lifter
    look.variants["top"] = top
    let figure = try PlaceholderCharacter.figure(wearing: look)
    for id: PartID in ["armL", "armR"] {
        let part = try figure.part(id)
        guard let sleeve = part.slots.firstIndex(of: "top") else { continue }
        let shoulder = try #require(part.art[part.slots.firstIndex(of: "body") ?? -1].shapes.first)
        let reach = (shoulder.stroke?.width ?? 0) / 2
        let cover = try #require(part.art[sleeve].shapes.first)
        let box = bounds(cover.path)
        #expect(cover.fill != nil, "\(top) \(id)")
        #expect(box.minX <= part.pivot.x - reach && box.maxX >= part.pivot.x + reach, "\(top) \(id)")
        #expect(box.minY <= part.pivot.y - reach && box.maxY >= part.pivot.y + reach, "\(top) \(id)")
    }
}

/// The arms are drawn in front of everything worn, so a sleeve's cloth stays inside its own
/// outline (its ends closed to the shoulder's circle along the radius) or within that circle,
/// which stays put on the body while the arm turns. Cloth past the outline (a round shoulder
/// lying on the chest) would turn with the arm with no line around it, as a blob over the
/// chest or a spike off the body when the arm is raised.
@Test(arguments: PlaceholderCharacter.variants(for: "top"))
func everySleeveKeepsInsideItsOutline(top: String) throws {
    var look = PlaceholderCharacter.lifter
    look.variants["top"] = top
    let figure = try PlaceholderCharacter.figure(wearing: look)
    for id: PartID in ["armL", "armR"] {
        let part = try figure.part(id)
        guard let sleeve = part.slots.firstIndex(of: "top") else { continue }
        let (pivot, circle) = (part.pivot, 11.4)
        let outline = try #require(part.art[sleeve].outline, "\(top) \(id)")
        let line = joined(outline.path)
        let closing = { (end: Point) -> [Point] in
            let reach = distance(end, pivot)
            guard reach > circle else { return [] }
            let scale = (circle - 0.8) / reach
            return [Point(x: pivot.x + (end.x - pivot.x) * scale, y: pivot.y + (end.y - pivot.y) * scale)]
        }
        let enclosed = closing(line[0]) + line + closing(line[line.count - 1]).reversed()
        let edges = Array(zip(enclosed, enclosed.dropFirst() + enclosed.prefix(1)))
        // Near the shoulder a sleeve may also cover the bare arm under it, wherever the arm turns.
        let body = try #require(part.slots.firstIndex(of: "body"))
        let limb = try #require(part.art[body].shapes.first.map { sampled($0.path) })
        let onArm = { (point: Point) in
            distance(point, pivot) <= 16.05
                && zip(limb, limb.dropFirst()).contains { segmentDistance(point, $0.0, $0.1) <= 10.95 + 0.05 }
        }
        for shape in part.art[sleeve].shapes where shape.fill != nil {
            for point in corners(shape.path) {
                let inside =
                    distance(point, pivot) <= circle + 0.05 || covers(enclosed, point) || onArm(point)
                    || edges.contains { segmentDistance(point, $0.0, $0.1) <= 0.05 }
                #expect(inside, "\(top) \(id) reaches \(point)")
            }
        }
    }
}

/// A line's pieces joined end to end where one starts where another ends, longest first.
private func joined(_ path: [PathElement]) -> [Point] {
    var pieces: [[Point]] = []
    for element in path {
        switch element {
        case .move(let point): pieces.append([point])
        case .line(let end), .quadCurve(let end, _), .curve(let end, _, _): pieces[pieces.count - 1].append(end)
        case .close: pieces[pieces.count - 1].append(pieces[pieces.count - 1][0])
        }
    }
    pieces.sort { $0.count > $1.count }
    var line = pieces.removeFirst()
    while let next = pieces.firstIndex(where: { $0.last == line.first || $0.first == line.last }) {
        let piece = pieces.remove(at: next)
        line = piece.last == line.first ? piece.dropLast() + line : line + piece.dropFirst()
    }
    return line
}

/// A line as points along it, each curve in 24 steps.
private func sampled(_ path: [PathElement]) -> [Point] {
    var (points, current) = ([Point](), Point(x: 0, y: 0))
    for element in path {
        switch element {
        case .move(let point), .line(let point):
            points.append(point)
            current = point
        case .quadCurve(let end, let control):
            for step in 1...24 {
                let (time, rest) = (Double(step) / 24, 1 - Double(step) / 24)
                points.append(
                    Point(
                        x: rest * rest * current.x + 2 * rest * time * control.x + time * time * end.x,
                        y: rest * rest * current.y + 2 * rest * time * control.y + time * time * end.y))
            }
            current = end
        case .curve(let end, _, _):
            points.append(end)
            current = end
        case .close: break
        }
    }
    return points
}

private func distance(_ one: Point, _ other: Point) -> Double {
    ((one.x - other.x) * (one.x - other.x) + (one.y - other.y) * (one.y - other.y)).squareRoot()
}

private func segmentDistance(_ point: Point, _ from: Point, _ end: Point) -> Double {
    let (across, down) = (end.x - from.x, end.y - from.y)
    let length = across * across + down * down
    guard length > 0 else { return distance(point, from) }
    let time = min(max(((point.x - from.x) * across + (point.y - from.y) * down) / length, 0), 1)
    return distance(point, Point(x: from.x + time * across, y: from.y + time * down))
}

/// Between the legs, a pair of shorts or trousers shows its own shade, not the top tucked
/// under it, which reads as the trousers coming apart.
@Test(arguments: PlaceholderCharacter.variants(for: "bottom"))
func theCrotchShowsTheBottomsOwnShade(bottom: String) throws {
    var look = PlaceholderCharacter.lifter
    look.variants["bottom"] = bottom
    let seat = try PlaceholderCharacter.figure(wearing: look).part("torso")
    let art = try #require(seat.slots.firstIndex(of: "bottom").map { seat.art[$0] })
    let crotch = Point(x: 120, y: 282)
    #expect(art.shapes.contains { $0.fill != nil && covers($0.path, crotch) })
}

private struct Box {
    var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
}

/// A path's points, where each of its pieces ends.
private func corners(_ path: [PathElement]) -> [Point] {
    path.compactMap { element -> Point? in
        switch element {
        case .move(let end), .line(let end), .quadCurve(let end, _), .curve(let end, _, _): end
        case .close: nil
        }
    }
}

/// Whether a closed path's outline, through its points, goes around `point` (even-odd).
private func covers(_ path: [PathElement], _ point: Point) -> Bool {
    covers(corners(path), point)
}

/// Whether a polygon through `corners` goes around `point` (even-odd).
private func covers(_ corners: [Point], _ point: Point) -> Bool {
    var inside = false
    for (from, next) in zip(corners, corners.dropFirst() + corners.prefix(1))
    where (from.y > point.y) != (next.y > point.y)
        && point.x < from.x + (point.y - from.y) / (next.y - from.y) * (next.x - from.x)
    {
        inside.toggle()
    }
    return inside
}

/// The box around a path's points; a circle's points sit on its edge, so it is the circle's.
private func bounds(_ path: [PathElement]) -> Box {
    var box = Box()
    for element in path {
        let point: Point
        switch element {
        case .move(let end), .line(let end), .quadCurve(let end, _), .curve(let end, _, _): point = end
        case .close: continue
        }
        box.minX = min(box.minX, point.x)
        box.maxX = max(box.maxX, point.x)
        box.minY = min(box.minY, point.y)
        box.maxY = max(box.maxY, point.y)
    }
    return box
}
