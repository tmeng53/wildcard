import Foundation

/// The one JSON setup for contract types, so the app and the backend agree on
/// key order. Contract types carry `Timestamp`, never `Date`, so no date strategy.
public enum WireJSON {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        JSONDecoder()
    }
}

/// Reads one item of a list, or nil when this build can't read it (a newer `version`,
/// a new `kind`), so one unreadable check-in doesn't fail a whole feed. Decode a feed as
/// `[Tolerant<CheckIn>]` and show the rest. Only for reading other people's data;
/// what this build writes is always a full, strict value.
///
/// Additive changes (a new key, a new sport) don't bump `version`; this build ignores
/// keys it doesn't know. Only a change old builds would misread bumps it.
public struct Tolerant<Value: Decodable & Sendable>: Decodable, Sendable {
    public let value: Value?

    public init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
