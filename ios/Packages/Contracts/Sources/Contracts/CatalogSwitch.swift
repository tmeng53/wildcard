import Foundation
import Synchronization

/// A global switch from the catalog's `switches`: on, off, or on every year between two days in
/// New York, as the API counts it. What only the public beta has follows one of its own
/// (`BetaFeature`), so each is turned off on the server, one by one, with no app release.
public struct CatalogSwitch: Hashable, Sendable {
    public enum Mode: Hashable, Sendable {
        case alwaysOn
        case alwaysOff
        /// On from `start` to `end`, both included, every year; a window may run over New Year.
        case schedule(start: MonthDay, end: MonthDay)
    }

    /// A day of the year, `MM-DD`.
    public struct MonthDay: Hashable, Comparable, Sendable {
        public let month: Int
        public let day: Int

        /// Nil for anything but `MM-DD` with a month and day that can be.
        public init?(_ text: String) {
            let parts = text.split(separator: "-")
            guard text.count == 5, parts.count == 2, let month = Int(parts[0]), let day = Int(parts[1]),
                (1...12).contains(month), (1...31).contains(day)
            else { return nil }
            (self.month, self.day) = (month, day)
        }

        public static func < (lhs: MonthDay, rhs: MonthDay) -> Bool {
            (lhs.month, lhs.day) < (rhs.month, rhs.day)
        }
    }

    public let id: String
    public let mode: Mode

    public init(id: String, mode: Mode) {
        (self.id, self.mode) = (id, mode)
    }

    /// Whether it is on, on `day` in New York.
    public func isOn(on day: LocalDay) -> Bool {
        switch mode {
        case .alwaysOn: return true
        case .alwaysOff: return false
        case .schedule(let start, let end):
            guard let today = MonthDay(String(day.description.suffix(5))) else { return false }
            return start <= end ? start <= today && today <= end : today >= start || today <= end
        }
    }

    /// The zone every switch's days are counted in.
    public static let zone = SquadTimeZone.newYorkClock
}

/// What only the public beta has, each on its own switch (Tracy, 2026-11-09). A switch the catalog
/// doesn't list is off, so one retired on the server stays gone.
public enum BetaFeature: String, CaseIterable, Sendable {
    /// 小队设置's 订阅 row with 「限时免费」.
    case freePlan = "betaFreePlan"
    /// 意见反馈's line on the mystery reward for feedback.
    case feedbackReward = "betaFeedbackReward"
}

/// The catalog's switches as the app last read them, for screens that show something only while
/// one is on. The app puts each catalog it reads here; the caller passes the moment.
public final class Switchboard: Sendable {
    /// The app's.
    public static let shared = Switchboard()

    private let current = Mutex<[CatalogSwitch]>([])

    public init() {}

    public func show(_ switches: [CatalogSwitch]) { current.withLock { $0 = switches } }

    /// Whether `id`'s switch is on at `moment`; off when the catalog doesn't list it.
    public func isOn(_ id: String, at moment: Date) -> Bool {
        let day = LocalDay(at: moment, in: CatalogSwitch.zone)
        return current.withLock { $0.first { $0.id == id } }?.isOn(on: day) ?? false
    }

    public func isOn(_ feature: BetaFeature, at moment: Date) -> Bool { isOn(feature.rawValue, at: moment) }
}
