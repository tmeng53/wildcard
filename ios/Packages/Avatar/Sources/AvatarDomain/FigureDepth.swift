import Foundation

extension Figure {
    /// Finds each part's twin, and checks that a part drawing only some of an arm is an arm.
    static func resolveTwins(_ built: inout [Part], _ parts: [Rig.Part]) throws(AvatarError) {
        for (index, part) in parts.enumerated() {
            if let twin = part.twin {
                guard let found = parts.firstIndex(where: { $0.id == twin }), parts[found].twin == nil,
                    parts[found].parent == part.parent
                else {
                    throw .malformedJSON(".parts: \(part.id) twins \(twin), which is no part with the same parent")
                }
                built[index].twin = found
            }
            if part.reach != nil, part.elbow == nil {
                throw .malformedJSON(".parts: \(part.id) has a reach but no elbow")
            }
        }
    }

    /// 1 where a part shows at its depth, 0 where it doesn't: a part that draws only some of
    /// an arm (`Rig.Part.reach`) shows only while the arm's `front` channel is 1; every other
    /// part, the whole arm behind the body too, always shows.
    func depth(_ index: Int, _ pose: Pose) -> Double {
        let part = parts[index]
        guard part.reach != nil else { return 1 }
        return pose.parts[part.twin ?? index].front < 0.5 ? 0 : 1
    }
}
