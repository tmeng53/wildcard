import Foundation

extension Figure {
    /// `Rig.Hides` with the arm found: its index in `parts`.
    public struct Hiding: Hashable, Sendable {
        public let arm: Int
        public let rule: Rig.Hides
    }

    /// Finds the arm each part that gives way to one follows, and each part's twin.
    static func resolveHides(_ built: inout [Part], _ parts: [Rig.Part]) throws(AvatarError) {
        for (index, part) in parts.enumerated() {
            if let twin = part.twin {
                guard let found = parts.firstIndex(where: { $0.id == twin }), parts[found].twin == nil,
                    parts[found].parent == part.parent
                else {
                    throw .malformedJSON(".parts: \(part.id) twins \(twin), which is no part with the same parent")
                }
                built[index].twin = found
                built[found].hasTwin = true
            }
            guard let rule = part.hides else { continue }
            guard let arm = parts.firstIndex(where: { $0.id == rule.part }) else {
                throw .malformedJSON(".parts: \(part.id) hides unknown part \(rule.part)")
            }
            built[index].hides = Hiding(arm: arm, rule: rule)
        }
    }

    /// 1 where a part shows at its depth, 0 where its arm is drawn at the other: an arm with a twin
    /// shows only in front (its `front` channel at 1), its twin only behind.
    func depth(_ index: Int, _ pose: Pose) -> Double {
        let part = parts[index]
        if let twin = part.twin { return pose.parts[twin].front < 0.5 ? 1 : 0 }
        return part.hasTwin && pose.parts[index].front < 0.5 ? 0 : 1
    }
}
