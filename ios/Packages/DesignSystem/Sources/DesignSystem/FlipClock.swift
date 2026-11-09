/// The rules of a flip clock: a row of number columns, each turning through its own range. A
/// column's range may depend on the columns before it (a date's day on its year and month), and
/// each column either wraps past its ends or stops at them. Pure values, so the cards only draw.
public struct FlipClock: Sendable {
    /// What a column does when it is turned past an end.
    public enum Ends: Hashable, Sendable {
        /// Past the last value comes the first again (minutes, months, days).
        case wrap
        /// It stays at the end (a birthday's year stops at 1900 and this year).
        case stop
    }

    /// One card: its range, worked out from the values of the columns before it, and its ends.
    public struct Column: Sendable {
        public let ends: Ends
        public let digits: Int
        private let range: @Sendable ([Int]) -> ClosedRange<Int>

        /// `digits` is how many figures the card shows, zero-padded (2 for `05`, 4 for a year).
        public init(
            ends: Ends,
            digits: Int,
            range: @escaping @Sendable (_ earlier: [Int]) -> ClosedRange<Int>
        ) {
            precondition(digits > 0, "a card shows at least one figure")
            self.ends = ends
            self.digits = digits
            self.range = range
        }

        /// A column whose range never changes.
        public init(_ range: ClosedRange<Int>, ends: Ends, digits: Int) {
            self.init(ends: ends, digits: digits) { _ in range }
        }

        /// The range this column turns through, given the values of the columns before it.
        public func range(after earlier: [Int]) -> ClosedRange<Int> {
            range(earlier)
        }
    }

    public let columns: [Column]

    public init(columns: [Column]) {
        precondition(!columns.isEmpty, "a flip clock has at least one column")
        self.columns = columns
    }

    /// `values` with each column held to its range, left to right, so a later range sees the
    /// earlier columns as they end up (February 30 becomes February 28 or 29). Missing values
    /// start at their column's first.
    public func settled(_ values: [Int]) -> [Int] {
        var settled: [Int] = []
        for (index, column) in columns.enumerated() {
            let range = column.range(after: settled)
            let value = index < values.count ? values[index] : range.lowerBound
            settled.append(min(max(value, range.lowerBound), range.upperBound))
        }
        return settled
    }

    /// `values` after turning `column` by `pages` (negative turns back), wrapping or stopping at
    /// its ends, with the later columns held to their new ranges.
    public func turning(_ values: [Int], column: Int, by pages: Int) -> [Int] {
        precondition(columns.indices.contains(column), "no such column")
        var next = settled(values)
        let range = columns[column].range(after: Array(next.prefix(column)))
        let moved = next[column] + pages
        switch columns[column].ends {
        case .stop:
            next[column] = min(max(moved, range.lowerBound), range.upperBound)
        case .wrap:
            let count = range.upperBound - range.lowerBound + 1
            let offset = ((moved - range.lowerBound) % count + count) % count
            next[column] = range.lowerBound + offset
        }
        return settled(next)
    }

    /// The card's figures for `value`, zero-padded to the column's digits.
    public func label(_ value: Int, column: Int) -> String {
        let text = String(value)
        let padding = max(columns[column].digits - text.count, 0)
        return String(repeating: "0", count: padding) + text
    }
}

extension FlipClock {
    /// Hour and minute on a 24-hour clock, both wrapping.
    public static let timeOfDay = FlipClock(columns: [
        Column(0...23, ends: .wrap, digits: 2),
        Column(0...59, ends: .wrap, digits: 2),
    ])

    /// Year, month and day: the year stops at `years`' ends, the month and day wrap, and the day
    /// runs to the length of that year's month.
    public static func date(years: ClosedRange<Int>) -> FlipClock {
        FlipClock(columns: [
            Column(years, ends: .stop, digits: 4),
            Column(1...12, ends: .wrap, digits: 2),
            Column(ends: .wrap, digits: 2) { earlier in
                1...daysIn(month: earlier[1], of: earlier[0])
            },
        ])
    }

    /// How many days a month has in the Gregorian calendar.
    public static func daysIn(month: Int, of year: Int) -> Int {
        switch month {
        case 2:
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return leap ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }
}
