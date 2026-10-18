import CheckInUI
import DesignSystemUI
import SwiftUI

/// The app target only wires packages together. It opens on 今天, backed by an in-memory squad
/// until the Backend adapter lands; `-styleguide` opens the design system's style guide instead.
@main
struct WildcardApp: App {
    @State private var today = TodayModel(
        service: InMemoryCheckInService.sampleSquad(now: .now),
        writer: DiceDisclaimerWriter(),
        photoSource: LaunchOptions.photoSource)

    var body: some Scene {
        WindowGroup {
            if LaunchOptions.showsStyleGuide {
                StyleGuideView()
            } else {
                TodayView(model: today)
            }
        }
    }
}
