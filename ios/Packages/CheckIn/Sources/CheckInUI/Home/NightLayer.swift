#if os(iOS)
import CheckInDomain
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The dark over the scene at night, as `LightsFlip` lifts or brings it back while a pull of the
/// cord plays: the tint and lamps, the lamp tubes flickering on and a faint flash at each bank.
/// It fills the screen: below the art, on a phone taller than it, the same tint goes on.
struct NightLayer: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let lightsOn: Bool
    let pull: TodayModel.LightsPull?
    /// The art's height on this screen.
    let artHeight: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: pull == nil)) { timeline in
            let (dark, lamps, flash) = levels(at: timeline.date)
            VStack(spacing: 0) {
                ZStack {
                    SceneArt(scene: theme, layer: .night).opacity(dark)
                    SceneArt(scene: theme, layer: .lamps).opacity(lamps)
                }
                .frame(height: artHeight)
                Color(NightTint.color).opacity(NightTint.opacity * dark)
            }
            .overlay { Color(role: .bgCanvas, in: theme).opacity(flash) }
        }
    }

    private func levels(at date: Date) -> (dark: Double, lamps: Double, flash: Double) {
        guard let pull else { return (lightsOn ? 0 : 1, 0, 0) }
        let flip = LightsFlip(isOn: pull.isOn, reduceMotion: reduceMotion)
        let seconds = date.timeIntervalSince(pull.start)
        return (flip.darkness(at: seconds), flip.lamps(at: seconds), flip.flash(at: seconds))
    }
}
#endif
