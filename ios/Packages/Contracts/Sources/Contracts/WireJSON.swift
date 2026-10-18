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
