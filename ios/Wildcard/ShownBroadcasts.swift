import Foundation

/// The broadcasts (群发通知) each member on this phone has seen drop in on 今天, so each shows
/// here once, by its id; marked once its banner is on screen, so one still waiting when the app
/// closes shows next time. Opening 通知 on any phone sees them too, so another phone shows only
/// those still unseen.
enum ShownBroadcasts {
    /// Ids kept per member: far more than ever run at once, so the list never grows without end.
    private static let kept = 50

    /// Whether `id`'s banner was shown to `member` on this phone.
    static func contains(_ id: String, for member: String) -> Bool {
        UserDefaults.standard.stringArray(forKey: key(member))?.contains(id) ?? false
    }

    /// `id`'s banner is on screen for `member`.
    static func mark(_ id: String, for member: String) {
        let defaults = UserDefaults.standard
        var shown = defaults.stringArray(forKey: key(member)) ?? []
        guard !shown.contains(id) else { return }
        shown.append(id)
        defaults.set(Array(shown.suffix(kept)), forKey: key(member))
    }

    private static func key(_ member: String) -> String { "shownBroadcasts.\(member)" }
}
