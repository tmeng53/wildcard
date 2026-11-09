/// A member's birthday, which they choose to give at sign-up or in 设置: a whole day, from 1900 to
/// today. The heart rate chart reads the age from it.
public struct Birthday: Hashable, Sendable, CustomStringConvertible {
    /// The API's `BIRTHDAY_EARLIEST`; `APIContract`'s parity test fails when the two differ.
    public static let earliest = LocalDay(calendarYear: 1900, month: 1, day: 1)

    public let day: LocalDay

    /// Refuses a day before `earliest` or after `today`, the phone's own.
    public init(_ day: LocalDay, today: LocalDay) throws(ContractsError) {
        guard day >= Self.earliest, day <= today else { throw .birthdayOutOfRange(day.description) }
        self.day = day
    }

    /// One the API sent, which it checked already.
    public init(sent day: LocalDay) {
        self.day = day
    }

    /// `YYYY-MM-DD`, as the API takes it.
    public var description: String { day.description }

    /// How old someone born on this day is on `today`, in whole years.
    public func age(on today: LocalDay) -> Int {
        let hadBirthday = (today.month, today.day) >= (day.month, day.day)
        return today.year - day.year - (hadBirthday ? 0 : 1)
    }
}

/// A birthday being picked on the flip clock (关于你, 设置 › 生日): year, month and day, which open
/// on 2000-01-01 (Tracy, 2026-11-08: never from Apple Health), or on the saved one. Sign-up saves
/// it only once the member turned a card, so the opening day is never saved by itself.
public struct BirthdayDraft: Hashable, Sendable {
    /// Where the clock opens when the member has no birthday yet.
    public static let opening = [2000, 1, 1]

    /// The years the clock turns through: from `Birthday.earliest`'s to today's.
    public static func years(through today: LocalDay) -> ClosedRange<Int> {
        Birthday.earliest.year...today.year
    }

    /// Year, month and day, as the clock holds them.
    public var values: [Int] {
        didSet { if values != oldValue { isTouched = true } }
    }
    /// Whether the member turned a card since it opened.
    public private(set) var isTouched = false

    public init(saved: Birthday? = nil) {
        values = saved.map { [$0.day.year, $0.day.month, $0.day.day] } ?? Self.opening
    }

    /// The picked day as a birthday, or nil when it isn't a day or comes after `today`.
    public func birthday(today: LocalDay) -> Birthday? {
        guard values.count == 3,
            let day = try? LocalDay(year: values[0], month: values[1], day: values[2])
        else { return nil }
        return try? Birthday(day, today: today)
    }
}
