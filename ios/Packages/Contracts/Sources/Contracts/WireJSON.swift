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

/// One item of a list read leniently, so one item doesn't fail a whole feed. Decode a
/// feed as `[Tolerant<CheckIn>]`: show the values, skip `.fromNewerApp` quietly (a newer
/// `version` or `kind`; the member will see it after updating), and log `.unreadable`,
/// which is data this build should have read and points at a bug. Only for reading other
/// people's data; what this build writes is always a full, strict value.
///
/// Additive changes (a new key, a new sport) don't bump `version`; this build ignores
/// keys it doesn't know. Only a change old builds would misread bumps it.
public enum Tolerant<Value: Decodable & Sendable>: Decodable, Sendable {
    case value(Value)
    case fromNewerApp
    /// Why it couldn't be read, for the log.
    case unreadable(String)

    public var value: Value? {
        if case .value(let value) = self { value } else { nil }
    }

    public init(from decoder: Decoder) throws {
        do {
            self = .value(try Value(from: decoder))
        } catch ContractsError.newerVersion, ContractsError.unknownKind {
            self = .fromNewerApp
        } catch {
            self = .unreadable(String(describing: error))
        }
    }
}
