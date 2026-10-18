import AvatarArt
import AvatarDomain
import Testing

/// The bundled files load and fit together, so a broken edit to them fails here, not on a phone.
@Test(arguments: PlaceholderCharacter.squad)
func everyOutfitBuilds(outfit: Outfit) throws {
    let figure = try PlaceholderCharacter.figure(wearing: outfit)
    #expect(
        figure.parts.map(\.id.rawValue) == [
            "shadow", "root", "tail", "legL", "legR", "torso", "head", "eyes", "mouthSmile", "mouthOpen", "propR",
            "armL", "armR",
        ])
    // Only the bear's hands are free, and only the cat has a tail.
    #expect(figure.parts[10].art.count == (outfit == PlaceholderCharacter.bear ? 0 : 1))
    #expect(figure.parts[2].art.count == (outfit == PlaceholderCharacter.cat ? 1 : 0))
    // The open mouth waits hidden until the cheer swaps it in.
    #expect(figure.layout(figure.restPose)[9].opacity == 0)
}

@Test(arguments: ["idle", "cheer"])
func everyClipBindsToTheRig(name: String) throws {
    let figure = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter)
    let clip = try PlaceholderCharacter.clip(name)
    #expect(clip.name == name)
    _ = try figure.bind(clip)
}

@Test func idleLoopsSeamlesslyAndCheerEndsAtRest() throws {
    let figure = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter)
    let idle = try figure.bind(PlaceholderCharacter.clip("idle"))
    let cheer = try figure.bind(PlaceholderCharacter.clip("cheer"))
    #expect(idle.clip.loops)
    #expect(!cheer.clip.loops)
    // The idle loop's last frame is its first, so the loop has no visible jump.
    #expect(figure.pose(idle, at: idle.clip.duration - 1e-9) == figure.pose(idle, at: 0))
    // The cheer lands back in the rest pose, so handing back to idle doesn't jump either.
    #expect(figure.pose(cheer, at: cheer.clip.duration) == figure.restPose)
    // Mid-cheer the figure is in the air with its arms out.
    let peak = figure.pose(cheer, at: 0.44)
    #expect(peak.parts[1].y == -36)
    #expect(peak.parts[11].rotation == 100)
    #expect(peak.parts[12].rotation == -100)
}

/// Every look stays inside the canvas through every frame of every clip, so a view sized to
/// the art never cuts off an ear or a racket. The bottom edge is left out: the shadow sits on it.
@Test(arguments: PlaceholderCharacter.squad)
func everyFrameStaysOnTheCanvas(outfit: Outfit) throws {
    let figure = try PlaceholderCharacter.figure(wearing: outfit)
    for name in ["idle", "cheer"] {
        let bound = try figure.bind(PlaceholderCharacter.clip(name))
        for frame in 0...Int(bound.clip.duration * 50) {
            let time = Double(frame) / 50
            for (part, placement) in zip(figure.parts, figure.layout(figure.pose(bound, at: time)))
            where placement.opacity > 0 {
                for shape in part.art.flatMap(\.shapes) {
                    let margin = (shape.stroke?.width ?? 0) / 2
                    for point in outline(shape.path).map(placement.transform.apply(to:)) {
                        #expect(
                            point.x - margin >= 0 && point.x + margin <= figure.width && point.y - margin >= 0,
                            "\(name) at \(time)s: \(part.id) reaches (\(point.x), \(point.y))")
                    }
                }
            }
        }
    }
}

/// Points along each segment of a path, curves sampled every tenth of the way.
private func outline(_ path: [PathElement]) -> [Point] {
    var points: [Point] = []
    var current = Point(x: 0, y: 0)
    func along(_ point: (Double) -> Point) {
        points += (1...10).map { point(Double($0) / 10) }
    }
    for element in path {
        switch element {
        case .move(let point), .line(let point):
            points.append(point)
            current = point
        case .quadCurve(let end, let control):
            let start = current
            along { way in
                let rest = 1 - way
                return Point(
                    x: rest * rest * start.x + 2 * rest * way * control.x + way * way * end.x,
                    y: rest * rest * start.y + 2 * rest * way * control.y + way * way * end.y)
            }
            current = end
        case .curve(let end, let control1, let control2):
            let start = current
            along { way in
                let rest = 1 - way
                return Point(
                    x: rest * rest * rest * start.x + 3 * rest * rest * way * control1.x + 3 * rest * way * way
                        * control2.x + way * way * way
                        * end.x,
                    y: rest * rest * rest * start.y + 3 * rest * rest * way * control1.y + 3 * rest * way * way
                        * control2.y + way * way * way * end.y
                )
            }
            current = end
        case .close: break
        }
    }
    return points
}
