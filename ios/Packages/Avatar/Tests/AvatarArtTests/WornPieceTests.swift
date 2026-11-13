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

/// Each arm is drawn over what the body wears only in front of its seam, and under the body
/// behind it (`Tuck`), so no round of sleeve lies on the chest however the arm turns. Every
/// sleeve's cloth starts at the seam's two ends (within its outline's width), so it leaves the body
/// there with no gap.
@Test(arguments: PlaceholderCharacter.variants(for: "top"))
func everySleeveStartsAtItsSeam(top: String) throws {
    var look = PlaceholderCharacter.lifter
    look.variants["top"] = top
    let figure = try PlaceholderCharacter.figure(wearing: look)
    for id: PartID in ["armL", "armR"] {
        let part = try figure.part(id)
        let seam = try #require(part.seam)
        #expect(part.tuck != nil, "\(top) \(id)")
        guard let sleeve = part.slots.firstIndex(of: "top") else { continue }
        let cloth = part.art[sleeve].shapes.filter { $0.fill != nil }.flatMap { corners($0.path) }
        for end in [seam.top, seam.armpit] {
            #expect(cloth.contains { distance($0, end) <= 2 }, "\(top) \(id) misses \(end)")
        }
    }
}

private func distance(_ one: Point, _ other: Point) -> Double {
    ((one.x - other.x) * (one.x - other.x) + (one.y - other.y) * (one.y - other.y)).squareRoot()
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
