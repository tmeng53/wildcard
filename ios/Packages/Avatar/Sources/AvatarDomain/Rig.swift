import Foundation

/// A part's name in a rig, such as `head` or `armL`.
public struct PartID: Hashable, Sendable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public init(from decoder: any Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }
}

/// Something worn or held that an outfit picks a variant for, such as `top` or `prop`.
public struct Slot: Hashable, Sendable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public init(from decoder: any Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }
}

/// How a character is put together: parts drawn on one canvas in their rest pose, each
/// turning around its pivot and carried by its parent. Read from `rig.json`.
public struct Rig: Hashable, Sendable {
    /// The only `version` of `rig.json` this build reads.
    public static let currentVersion = 1

    public var width: Double
    public var height: Double
    /// Back to front: the order parts are drawn in, independent of who carries whom.
    public var parts: [Part]
    /// The variant a slot wears when an outfit leaves it out, such as round eyes: a face
    /// every character has unless the look picks another.
    public var defaults: [Slot: String]
    /// The skin a held thing's grip is drawn in (the peach body's hand), which a layer with
    /// `hand` repaints in the wearer's own hand colors. Nil when no layer needs it.
    public var skin: Skin?

    /// A fill and its outline.
    public struct Skin: Hashable, Sendable {
        public var fill: RGBAColor
        public var stroke: RGBAColor

        public init(fill: RGBAColor, stroke: RGBAColor) {
            (self.fill, self.stroke) = (fill, stroke)
        }
    }

    public struct Part: Hashable, Sendable {
        public var id: PartID
        public var parent: PartID?
        /// The point the part turns and scales around, in canvas coordinates.
        public var pivot: Point
        /// How opaque the part is when no clip says otherwise; 0 hides it, as for a
        /// second mouth that a clip swaps in.
        public var opacity: Double
        public var layers: [Layer]

        public init(id: PartID, parent: PartID? = nil, pivot: Point, opacity: Double = 1, layers: [Layer] = []) {
            (self.id, self.parent, self.pivot, self.opacity, self.layers) = (id, parent, pivot, opacity, layers)
        }
    }

    /// One art file drawn for a part. Without a slot it is the character's own
    /// (`base/<art>.svg`); with one it comes from the variant the outfit picks
    /// (`<slot>/<variant>/<art>.svg`), and a variant may have no file for that part.
    public struct Layer: Hashable, Sendable, Codable {
        public var slot: Slot?
        public var art: String
        /// The part whose hand this layer is held in, such as `armR` for the fist around a
        /// racket's handle: its colors in the rig's `skin` become that hand's, so a cat holds
        /// a racket in a ginger paw. The hand is the last shape of the part's `body` art.
        public var hand: PartID?

        public init(slot: Slot? = nil, art: String, hand: PartID? = nil) {
            (self.slot, self.art, self.hand) = (slot, art, hand)
        }
    }

    public init(
        width: Double, height: Double, parts: [Part], defaults: [Slot: String] = [:], skin: Skin? = nil
    ) {
        (self.width, self.height, self.parts, self.defaults, self.skin) = (width, height, parts, defaults, skin)
    }

    public static func decode(_ data: Data) throws(AvatarError) -> Rig {
        let file: RigFile = try decodeJSON(data, version: currentVersion, shape: RigFile.shape)
        return Rig(
            width: file.canvas.width, height: file.canvas.height,
            parts: file.parts.map { part in
                Part(
                    id: part.id, parent: part.parent, pivot: part.pivot.point,
                    opacity: part.opacity ?? 1, layers: part.layers ?? [])
            },
            defaults: Dictionary(uniqueKeysWithValues: (file.defaults ?? [:]).map { (Slot($0.key), $0.value) }),
            skin: try file.skin.map { skin throws(AvatarError) in
                guard let fill = RGBAColor(hex: skin.fill), let stroke = RGBAColor(hex: skin.stroke) else {
                    throw .malformedJSON(".skin: not a #rrggbb color")
                }
                return Skin(fill: fill, stroke: stroke)
            })
    }
}

private struct RigFile: Decodable {
    let canvas: Canvas
    let parts: [PartFile]
    let defaults: [String: String]?
    let skin: SkinFile?

    static let shape = JSONShape.object([
        "version": .value,
        "canvas": .object(["width": .value, "height": .value]),
        // Keyed by slot, so any key goes.
        "defaults": .value,
        "skin": .object(["fill": .value, "stroke": .value]),
        "parts": .array(
            .object([
                "id": .value, "parent": .value, "pivot": .value, "opacity": .value,
                "layers": .array(.object(["slot": .value, "art": .value, "hand": .value])),
            ])),
    ])

    struct Canvas: Decodable {
        let width: Double
        let height: Double
    }

    struct SkinFile: Decodable {
        let fill: String
        let stroke: String
    }

    struct PartFile: Decodable {
        let id: PartID
        let parent: PartID?
        let pivot: Pair
        let opacity: Double?
        let layers: [Rig.Layer]?
    }
}

/// `[x, y]`.
struct Pair: Decodable {
    let point: Point

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        point = Point(x: try container.decode(Double.self), y: try container.decode(Double.self))
        guard container.isAtEnd else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "expected [x, y]")
        }
    }
}

private struct Versioned: Decodable {
    let version: Int
}

/// The keys a JSON file may use. `Decodable` skips keys it doesn't know, so a misspelt
/// optional key such as `"parnet"` would load as if it were absent; checking the keys
/// first turns that into an error that names it.
public indirect enum JSONShape: Sendable {
    case object([String: JSONShape])
    case array(JSONShape)
    /// A number, string or anything else `Decodable` checks on its own.
    case value

    func check(_ json: Any, at path: String = "") throws(AvatarError) {
        switch self {
        case .value: return
        case .array(let element):
            guard let items = json as? [Any] else { return }
            for (index, item) in items.enumerated() { try element.check(item, at: "\(path)[\(index)]") }
        case .object(let keys):
            guard let object = json as? [String: Any] else { return }
            for key in object.keys.sorted() {
                guard let shape = keys[key] else { throw .malformedJSON("\(path): unknown key \"\(key)\"") }
                if let value = object[key] { try shape.check(value, at: "\(path).\(key)") }
            }
        }
    }
}

/// Reads the version first, so a newer file says so instead of failing on a field it added.
public func decodeJSON<T: Decodable>(_ data: Data, version expected: Int, shape: JSONShape) throws(AvatarError) -> T {
    do {
        let version = try JSONDecoder().decode(Versioned.self, from: data).version
        guard version == expected else { throw AvatarError.unsupportedVersion(version) }
        try shape.check(try JSONSerialization.jsonObject(with: data))
        return try JSONDecoder().decode(T.self, from: data)
    } catch let error as AvatarError {
        throw error
    } catch DecodingError.keyNotFound(let key, let context) {
        throw .malformedJSON("missing \(path(context.codingPath + [key]))")
    } catch DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context),
        DecodingError.dataCorrupted(let context)
    {
        throw .malformedJSON("\(path(context.codingPath)): \(context.debugDescription)")
    } catch {
        throw .malformedJSON("\(error)")
    }
}

private func path(_ keys: [any CodingKey]) -> String {
    keys.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
}
