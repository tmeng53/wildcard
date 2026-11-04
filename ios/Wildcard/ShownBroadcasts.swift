import Foundation

/// The broadcasts (群发通知) this phone has dropped in on 今天, so each shows here once, by its id.
/// Opening 通知 on any phone sees them too, so another phone shows only those still unseen.
enum ShownBroadcasts {
    private static let key = "shownBroadcasts"
    /// Ids kept: far more than ever run at once, so the list never grows without end.
    private static let kept = 50

    /// Whether `id` is shown for the first time on this phone; marks it shown.
    static func first(_ id: String) -> Bool {
        let defaults = UserDefaults.standard
        var shown = defaults.stringArray(forKey: key) ?? []
        guard !shown.contains(id) else { return false }
        shown.append(id)
        defaults.set(Array(shown.suffix(kept)), forKey: key)
        return true
    }
}
