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

        public init(slot: Slot? = nil, art: String) {
            (self.slot, self.art) = (slot, art)
        }
    }

    public init(width: Double, height: Double, parts: [Part]) {
        (self.width, self.height, self.parts) = (width, height, parts)
    }

    public static func decode(_ data: Data) throws(AvatarError) -> Rig {
        let file: RigFile = try decodeJSON(data, version: currentVersion, shape: RigFile.shape)
        return Rig(
            width: file.canvas.width, height: file.canvas.height,
            parts: file.parts.map { part in
                Part(
                    id: part.id, parent: part.parent, pivot: part.pivot.point,
                    opacity: part.opacity ?? 1, layers: part.layers ?? [])
            })
    }
}

private struct RigFile: Decodable {
    let canvas: Canvas
    let parts: [PartFile]

    static let shape = JSONShape.object([
        "version": .value,
        "canvas": .object(["width": .value, "height": .value]),
        "parts": .array(
            .object([
                "id": .value, "parent": .value, "pivot": .value, "opacity": .value,
                "layers": .array(.object(["slot": .value, "art": .value])),
            ])),
    ])

    struct Canvas: Decodable {
        let width: Double
        let height: Double
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
indirect enum JSONShape: Sendable {
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
func decodeJSON<T: Decodable>(_ data: Data, version expected: Int, shape: JSONShape) throws(AvatarError) -> T {
    do {
        let version = try JSONDecoder().decode(Versioned.self, from: data).version
        guard version == expected else { throw AvatarError.unsupportedVersion(version) }
        try shape.check(try JSONSerialization.jsonObject(with: data))
        return try JSONDecoder().decode(T.self, from: data)
    } catch let error as AvatarError {
        throw error
    } catch let DecodingError.keyNotFound(key, context) {
        throw .malformedJSON("missing \(path(context.codingPath + [key]))")
    } catch let DecodingError.typeMismatch(_, context), let DecodingError.valueNotFound(_, context),
        let DecodingError.dataCorrupted(context)
    {
        throw .malformedJSON("\(path(context.codingPath)): \(context.debugDescription)")
    } catch {
        throw .malformedJSON("\(error)")
    }
}

private func path(_ keys: [any CodingKey]) -> String {
    keys.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
}
