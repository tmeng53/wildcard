import Foundation

extension Figure {
    /// Finds each part's twin, and marks the part it names as the one drawn in front.
    static func resolveTwins(_ built: inout [Part], _ parts: [Rig.Part]) throws(AvatarError) {
        for (index, part) in parts.enumerated() {
            if let twin = part.twin {
                guard let found = parts.firstIndex(where: { $0.id == twin }), parts[found].twin == nil,
                    parts[found].parent == part.parent
                else {
                    throw .malformedJSON(".parts: \(part.id) twins \(twin), which is no part with the same parent")
                }
                built[index].twin = found
                built[found].front = true
            }
        }
    }

    /// Where an arm's front copy is drawn: past the elbow, so only the forearm and what it holds
    /// come in front of the body while the shoulder and sleeve stay behind it. A swap of depth then
    /// shows only where the forearm crosses the body, and a move keys it while the forearm is
    /// clear of it, so the swap can't be seen (the shoulder was what jumped).
    func forearm(_ shoulder: Point, _ elbow: Rig.Elbow, _ carrier: Transform) -> [Point] {
        let (alongX, alongY) = (elbow.hand.x - shoulder.x, elbow.hand.y - shoulder.y)
        let length = (alongX * alongX + alongY * alongY).squareRoot()
        guard length > 0 else { return [] }
        let (unitX, unitY) = (alongX / length, alongY / length)
        // A wide band from the elbow out past the hand and anything it holds, before the bend.
        let corners = [(-Self.reach, 0.0), (Self.reach, 0), (Self.reach, Self.reach), (-Self.reach, Self.reach)]
        return corners.map { corner in
            let (across, along) = corner
            return carrier.apply(
                to: Point(
                    x: elbow.point.x - unitY * across + unitX * along,
                    y: elbow.point.y + unitX * across + unitY * along))
        }
    }

    /// How far the forearm's area reaches, in canvas points: past any prop a hand holds.
    static let reach = 400.0

    /// 1 where a part shows at its depth, 0 where it doesn't: an arm's front copy (the part a
    /// twin names) shows only while its `front` channel is 1; every other part, the copy behind
    /// the body too, always shows.
    func depth(_ index: Int, _ pose: Pose) -> Double {
        guard parts[index].front else { return 1 }
        return pose.parts[index].front < 0.5 ? 0 : 1
    }
}
