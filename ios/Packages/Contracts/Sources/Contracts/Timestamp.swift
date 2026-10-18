import Foundation

/// A moment in UTC, held as whole milliseconds so it survives the wire unchanged.
/// Encodes as ISO 8601 with milliseconds (`2025-10-18T00:00:00.123Z`); decodes any
/// ISO 8601 offset and any number of fraction digits, keeping the first three, so
/// Postgres `timestamptz` values (`...00.123456+00:00`) read as-is.
public struct Timestamp: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let millisecondsSince1970: Int64

    public init(millisecondsSince1970: Int64) {
        self.millisecondsSince1970 = millisecondsSince1970
    }

    /// Drops anything finer than a millisecond.
    public init(_ date: Date) {
        millisecondsSince1970 = Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
    }

    public var date: Date { Date(timeIntervalSince1970: Double(millisecondsSince1970) / 1000) }

    public init(_ text: String) throws(ContractsError) {
        // Split off the fraction so the whole-second part parses exactly.
        var whole = text
        var millis: Int64 = 0
        if let dot = text.firstIndex(of: "."), let tIndex = text.firstIndex(of: "T"), dot > tIndex {
            let digits = text[text.index(after: dot)...].prefix(while: \.isASCIIDigit)
            guard !digits.isEmpty else { throw .invalidTimestamp(text) }
            let padded = (digits.prefix(3) + String(repeating: "0", count: max(0, 3 - digits.count)))
            millis = Int64(padded) ?? 0
            whole = String(text[..<dot]) + String(text[digits.endIndex...])
        }
        guard let seconds = try? Date.ISO8601FormatStyle().parse(whole) else {
            throw .invalidTimestamp(text)
        }
        millisecondsSince1970 = Int64(seconds.timeIntervalSince1970) * 1000 + millis
    }

    public var description: String {
        let (seconds, millis) = millisecondsSince1970.quotientAndRemainder(dividingBy: 1000)
        let (wholeSeconds, fraction) = millis < 0 ? (seconds - 1, millis + 1000) : (seconds, millis)
        let base = Date(timeIntervalSince1970: Double(wholeSeconds)).formatted(.iso8601)  // ends in "Z"
        let fractionText = String(fraction + 1000).dropFirst()
        return "\(base.dropLast()).\(fractionText)Z"
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.millisecondsSince1970 < rhs.millisecondsSince1970
    }

    public init(from decoder: Decoder) throws {
        try self.init(try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
