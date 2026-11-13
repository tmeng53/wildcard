import Foundation

/// How the app and the API name one tagged place (Tracy, 2026-11-12): `apple:` and Apple Maps'
/// identifier, or `squad:` and the id of a place a squad added itself. Its page, its scores and
/// 收藏 are all kept by it.
public struct PlaceKey: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    /// Nil for anything the API wouldn't take as a place's key.
    public init?(rawValue: String) {
        if rawValue.hasPrefix(Self.applePrefix) {
            let id = rawValue.dropFirst(Self.applePrefix.count)
            guard (1...200).contains(id.unicodeScalars.count), id.unicodeScalars.allSatisfy(Self.isAppleIDCharacter)
            else { return nil }
        } else if rawValue.hasPrefix(Self.squadPrefix) {
            let id = String(rawValue.dropFirst(Self.squadPrefix.count))
            guard UUID(uuidString: id) != nil, id == id.lowercased() else { return nil }
        } else {
            return nil
        }
        self.rawValue = rawValue
    }

    /// The key of the place Apple Maps knows by `id`; nil for an id the API wouldn't take.
    public static func apple(_ id: String) -> PlaceKey? { PlaceKey(rawValue: applePrefix + id) }

    public var description: String { rawValue }

    private static let applePrefix = "apple:"
    private static let squadPrefix = "squad:"

    private static func isAppleIDCharacter(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar)
            || scalar == "." || scalar == "_" || scalar == "-"
    }
}

extension Place {
    /// The place's key: by Apple Maps' id; nil for a place Maps gave no id, which has no page.
    public var key: PlaceKey? { appleID.flatMap(PlaceKey.apple) }
}
