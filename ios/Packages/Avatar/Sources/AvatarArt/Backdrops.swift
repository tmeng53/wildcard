import AvatarDomain
import Foundation

/// The colours a head may sit on, inside its circle (`AvatarUI`'s `MemberHead`), by id. Read from
/// `avatar/backdrops.json`, so the list is art an admin puts (`put_art`) like any other file;
/// a coach picks one in `coaches/<id>/backdrop.json`, and a member may pick one the same way
/// later. A head without one sits on the page's own colour.
public struct Backdrops: Hashable, Sendable {
    /// In the order a picker would show them.
    public let entries: [Backdrop]

    public init(_ entries: [Backdrop]) {
        self.entries = entries
    }

    /// The colour named `id`; nil for an id the list doesn't have.
    public func color(_ id: String) -> RGBAColor? {
        entries.first { $0.id == id }?.color
    }

    /// The only `version` of the list this build reads.
    public static let currentVersion = 1

    /// `{"version": 1, "backdrops": [{"id": "tennis", "color": "#DDE6CC"}]}`. An entry whose colour
    /// isn't `#rrggbb` is refused, so a list that reads is a list that draws.
    public static func decode(_ data: Data) throws(AvatarError) -> Backdrops {
        let file: File = try decodeJSON(data, version: currentVersion, shape: File.shape)
        var entries: [Backdrop] = []
        for entry in file.backdrops {
            guard let color = RGBAColor(hex: entry.color) else {
                throw .malformedJSON(".backdrops.\(entry.id): not a #rrggbb color")
            }
            entries.append(Backdrop(id: entry.id, color: color))
        }
        return Backdrops(entries)
    }

    private struct File: Decodable {
        static let shape = JSONShape.object([
            "version": .value, "backdrops": .array(.object(["id": .value, "color": .value])),
        ])

        let backdrops: [BackdropEntry]
    }
}

/// One colour of the list as written.
private struct BackdropEntry: Decodable {
    let id: String
    let color: String
}

/// One colour of the list.
public struct Backdrop: Hashable, Sendable {
    public let id: String
    public let color: RGBAColor

    public init(id: String, color: RGBAColor) {
        (self.id, self.color) = (id, color)
    }
}

/// Which backdrop a head picks: `{"version": 1, "backdrop": "tennis"}`, a coach's
/// `coaches/<id>/backdrop.json`.
public enum BackdropPick {
    /// The only `version` this build reads.
    public static let currentVersion = 1

    public static func decode(_ data: Data) throws(AvatarError) -> String {
        let file: File = try decodeJSON(data, version: currentVersion, shape: File.shape)
        return file.backdrop
    }

    private struct File: Decodable {
        static let shape = JSONShape.object(["version": .value, "backdrop": .value])
        let backdrop: String
    }
}

extension PlaceholderCharacter {
    /// The backdrops heads pick from; empty when the list can't be read.
    public static var backdrops: Backdrops {
        (try? file("backdrops.json")).flatMap { try? Backdrops.decode($0) } ?? Backdrops([])
    }
}
