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
            }
            guard let rule = part.hides else { continue }
            guard let arm = parts.firstIndex(where: { $0.id == rule.part }) else {
                throw .malformedJSON(".parts: \(part.id) hides unknown part \(rule.part)")
            }
            built[index].hides = Hiding(arm: arm, rule: rule)
        }
    }
}
