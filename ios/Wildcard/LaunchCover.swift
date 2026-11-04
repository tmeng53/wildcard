import DesignSystem
import DesignSystemUI
import SwiftUI

/// What every launch shows until the app knows which screen to open, and on which scene
/// (design A 字母浪): the logo lifts on graphite, WILDCARD pops up under it, and the tickets
/// and letters wave until it is ready. The system's launch screen is the same graphite and logo
/// (`UILaunchScreen` in `Config/Info.plist`), so the app opens without a white frame and the
/// logo moves on from where it stood.
struct LaunchCover: View {
    /// When the cover came up, so two covers over each other (signing in, then 今天 opening
    /// under it) draw the same frame; without it, when this one appeared.
    var start: Date?
    @State private var appeared = Date.now

    var body: some View {
        LaunchWordmark(start: start ?? appeared)
            // Centred on the whole screen, as the system's launch screen centres its image.
            .ignoresSafeArea()
            .accessibilityIdentifier("launch.cover")
    }
}

extension AppModel {
    /// Under the launch cover, waits until WILDCARD has landed on it (`LaunchWave.entrance`), so a
    /// fast open shows the word whole, and 今天's own entrance starts once the cover fades, not
    /// under it. The open screen doesn't wait: its sprint is its own WILDCARD.
    func letLaunchWordLand() async {
        guard isStarting else { return }
        let left = LaunchWave.entrance - Date.now.timeIntervalSince(coverSince)
        if left > 0 { try? await Task.sleep(for: .seconds(left)) }
    }
}

extension AppModel.Screen {
    /// Whether this is the launch cover's screen.
    var isStarting: Bool {
        if case .starting = self { return true }
        return false
    }
}
