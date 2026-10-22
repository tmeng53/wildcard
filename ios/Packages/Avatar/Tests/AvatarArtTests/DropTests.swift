import AvatarArt
import AvatarDomain
import AvatarLooks
import Testing

/// The drop starts wholly above the canvas with the shadow small on the ground, touches down at
/// `dropLands`, squashes, and ends at rest; from touch-down on, every look stays on its canvas.
@Test(arguments: Looks.squad)
func theDropFallsInAndLandsAtRest(look: Outfit) throws {
    let figure = try PlaceholderCharacter.figure(wearing: look)
    let drop = try figure.bind(PlaceholderCharacter.drop())
    #expect(!drop.clip.loops)
    let (root, shadow) = (try figure.index("root"), try figure.index("shadow"))
    let start = figure.pose(drop, at: 0)
    for (part, placement) in zip(figure.parts, figure.layout(start)) where placement.opacity > 0 && part.id != "shadow"
    {
        for point in part.art.flatMap(\.shapes).flatMap({ outline($0.path) }).map(placement.transform.apply(to:)) {
            #expect(point.y < 0, "\(part.id)")
        }
    }
    #expect(start.parts[shadow].y == 0 && start.parts[shadow].scaleX < 0.5)
    #expect(figure.pose(drop, at: PlaceholderCharacter.dropLands).parts[root].y == 0)
    // It falls under gravity: three times as far in the second half of the fall as in the first.
    let half = figure.pose(drop, at: PlaceholderCharacter.dropLands / 2).parts[root].y
    #expect(abs((0 - half) / (half - start.parts[root].y) - 3) < 0.1)
    let squash = (0...20).map { figure.pose(drop, at: PlaceholderCharacter.dropLands + Double($0) / 100) }
    #expect(squash.map { $0.parts[root].scaleY }.min() ?? 1 < 0.75)
    #expect(nearlyEqual(figure.pose(drop, at: drop.clip.duration), figure.restPose))
    for frame in Int((PlaceholderCharacter.dropLands * 50).rounded(.up))...Int(drop.clip.duration * 50) {
        let time = Double(frame) / 50
        for (part, placement) in zip(figure.parts, figure.layout(figure.pose(drop, at: time)))
        where placement.opacity > 0 {
            for shape in part.art.flatMap(\.shapes) {
                let margin = (shape.stroke?.width ?? 0) / 2
                for point in outline(shape.path).map(placement.transform.apply(to:)) {
                    #expect(
                        point.x - margin >= 0 && point.x + margin <= figure.width && point.y - margin >= 0
                            && (part.id == "shadow" || point.y + margin <= figure.height),
                        "at \(time)s: \(part.id) reaches (\(point.x), \(point.y))")
                }
            }
        }
    }
}
