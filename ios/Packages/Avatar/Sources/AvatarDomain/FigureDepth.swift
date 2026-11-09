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

    /// How much a part shows at its depth: an arm's front copy (the part a twin names) as much
    /// as its `front` channel, so it fades in over the copy behind as the arm crosses the body;
    /// every other part, the copy behind the body too, always shows.
    func depth(_ index: Int, _ pose: Pose) -> Double {
        guard parts[index].front else { return 1 }
        return min(max(pose.parts[index].front, 0), 1)
    }
}
