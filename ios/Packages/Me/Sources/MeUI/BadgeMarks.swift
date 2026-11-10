import Contracts
import Foundation
import MeDomain
import Observation

/// What this phone saw of the member's own badge board: which badges were opened, for NEW, kept
/// in the app's defaults per member (only in memory for the sample squad and previews); and the
/// turns of 我's player card to the board a notice asks for.
@MainActor @Observable
public final class BadgeMarks {
    private let defaults: UserDefaults?
    private let key: String
    /// Nil before the first look on this phone.
    private var seen: Set<String>?
    /// A notice asked for the board: 我's card turns to it, and unsets it.
    public var boardRequested = false

    /// Marks for `member` in `defaults`; nil `member` keeps them in memory only.
    public init(member: String?, defaults: UserDefaults = .standard) {
        self.defaults = member == nil ? nil : defaults
        key = "badges.seen.\(member ?? "")"
        seen = self.defaults?.stringArray(forKey: key).map(Set.init)
    }

    /// The badges on `board` that wear NEW. The first look takes what came before the last week
    /// as seen.
    public func news(on board: TitleBoard, now: Date = .now) -> Set<String> {
        let seen = seen ?? firstLook(board, now: now)
        return BadgeNews.unseen(on: board, seen: seen)
    }

    /// Turns 我's player card to its badge board.
    public func showBoard() { boardRequested = true }

    /// A badge on `board` opened: no longer NEW.
    public func see(_ mark: String, on board: TitleBoard, now: Date = .now) {
        let marks = (seen ?? firstLook(board, now: now)).union([mark])
        seen = marks
        defaults?.set(marks.sorted(), forKey: key)
    }

    /// Everything but what came in the last week, as of `now`.
    private func firstLook(_ board: TitleBoard, now: Date) -> Set<String> {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: now)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
            let today = try? LocalDay(year: year, month: month, day: day)
        else { return [] }
        return BadgeNews.seenAtFirstLook(board, now: now, today: today)
    }
}
