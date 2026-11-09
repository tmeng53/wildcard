/// A member's birthday, which they choose to give at sign-up or in 设置: a whole day, from 1900 to
/// today. The heart rate chart reads the age from it.
public struct Birthday: Hashable, Sendable, CustomStringConvertible {
    /// The API's earliest; `APIContract`'s tests fail when the two differ.
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
