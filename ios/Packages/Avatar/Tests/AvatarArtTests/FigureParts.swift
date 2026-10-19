import AvatarDomain
import Testing

/// Parts by id, so tests read the same when the rig gains a part.
extension Figure {
    func index(_ id: PartID) throws -> Int {
        try #require(parts.firstIndex { $0.id == id })
    }

    func part(_ id: PartID) throws -> Part {
        parts[try index(id)]
    }
}
