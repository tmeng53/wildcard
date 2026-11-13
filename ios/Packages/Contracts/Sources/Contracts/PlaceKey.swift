import Foundation

/// Which place, as the API names it: `apple:` and Apple Maps' identifier, or `squad:` and the id
/// of a place one of the squad's members added (Tracy, 2026-11-12). A place's page, its ratings
/// and 收藏 all address a place by it.
public struct PlaceKey: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    /// Nil for anything the API wouldn't take as a key.
    public init?(rawValue: String) {
        if rawValue.hasPrefix(Self.apple) {
            let id = rawValue.dropFirst(Self.apple.count)
            guard (1...200).contains(id.unicodeScalars.count), id.unicodeScalars.allSatisfy(Self.isAppleCharacter)
            else { return nil }
        } else if rawValue.hasPrefix(Self.squad) {
            let id = String(rawValue.dropFirst(Self.squad.count))
            // Lowercase, as the API writes a uuid.
            guard let uuid = UUID(uuidString: id), uuid.uuidString.lowercased() == id else { return nil }
        } else {
            return nil
        }
        self.rawValue = rawValue
    }

    /// Apple Maps' place, by its identifier; nil for an id the API wouldn't take.
    public init?(appleID: String) {
        self.init(rawValue: Self.apple + appleID)
    }

    /// A place the squad added, by its id.
    public init(squadPlace id: UUID) {
        rawValue = Self.squad + id.uuidString.lowercased()
    }

    private static let apple = "apple:"
    private static let squad = "squad:"

    private static func isAppleCharacter(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar)
            || scalar == "." || scalar == "_" || scalar == "-"
    }
}

extension Place {
    /// How the API names it: by Apple Maps' id. Nil for a place Maps gave no id, which no squad
    /// numbers can be kept for.
    public var key: PlaceKey? { appleID.flatMap(PlaceKey.init(appleID:)) }
}
