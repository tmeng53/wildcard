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

    /// 1 where a part shows at its depth, 0 where it doesn't: an arm's front copy (the part a
    /// twin names) shows only while its `front` channel is 1; every other part, the copy behind
    /// the body too, always shows.
    func depth(_ index: Int, _ pose: Pose) -> Double {
        guard parts[index].front else { return 1 }
        return pose.parts[index].front < 0.5 ? 0 : 1
    }
}
