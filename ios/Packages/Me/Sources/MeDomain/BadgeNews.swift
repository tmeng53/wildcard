import Contracts
import Foundation

/// Which badges on the member's own board wear NEW: each is new until it is opened on this
/// phone, and a badge got again (×N one more) is new again. A phone's first look takes what came
/// before the last week as seen, so a board full of old badges doesn't all light up at once.
public enum BadgeNews {
    /// How far back a badge got before the first look still counts as new.
    public static let firstLookWindow: TimeInterval = 7 * 24 * 60 * 60

    /// A team badge's mark, by its id and how many times it was got.
    public static func key(_ badge: TeamBadge) -> String { "team.\(badge.id).\(badge.times)" }

    /// A title's mark, by its words and how many times it was won.
    public static func key(_ title: BoardTitle) -> String { "title.\(title.title).\(title.times)" }

    /// Every mark on the board.
    public static func keys(on board: TitleBoard) -> Set<String> {
        Set(board.teamBadges.map(key) + board.titles.map(key))
    }

    /// What a phone's first look takes as seen: every badge but those got in the last week. A team
    /// badge from a server before `latestAt` counts as old; a title as got the Monday after the
    /// week it was won.
    public static func seenAtFirstLook(_ board: TitleBoard, now: Date, today: LocalDay) -> Set<String> {
        let since = now.addingTimeInterval(-firstLookWindow)
        let oldBadges = board.teamBadges.filter { ($0.latestAt ?? .distantPast) < since }
        let weekAgo = today.adding(days: -7)
        let oldTitles = board.titles.filter { title in
            guard let latest = title.weeks.first?.weekStart else { return true }
            return latest.adding(days: 7) < weekAgo
        }
        return Set(oldBadges.map(key) + oldTitles.map(key))
    }

    /// The marks on the board not yet seen.
    public static func unseen(on board: TitleBoard, seen: Set<String>) -> Set<String> {
        keys(on: board).subtracting(seen)
    }
}
