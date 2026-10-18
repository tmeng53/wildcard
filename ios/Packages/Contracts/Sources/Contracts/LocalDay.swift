/// A calendar day in the member's own time zone. A check-in counts for the day the
/// member lived it, not a UTC day, so a 11pm workout in Toronto stays on that day.
/// Encodes as `YYYY-MM-DD`.
public struct LocalDay: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) throws(ContractsError) {
        guard (1...12).contains(month), (1...Self.daysIn(month: month, year: year)).contains(day),
              (1970...9999).contains(year)
        else { throw .invalidDay(Self.format(year, month, day)) }
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ text: String) throws(ContractsError) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { throw .invalidDay(text) }
        try self.init(year: year, month: month, day: day)
    }

    public init(from decoder: Decoder) throws {
        try self.init(try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    public var description: String { Self.format(year, month, day) }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    private static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    private static func format(_ year: Int, _ month: Int, _ day: Int) -> String {
        func pad(_ value: Int, _ width: Int) -> String {
            let digits = String(value)
            return String(repeating: "0", count: max(0, width - digits.count)) + digits
        }
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
    }
}
