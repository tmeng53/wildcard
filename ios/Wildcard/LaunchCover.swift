import DesignSystem
import DesignSystemUI
import SwiftUI

/// What every launch shows until the app knows which screen to open, and on which scene: the
/// logo turning on graphite (design A 两张票). The system's launch screen is the same graphite
/// and logo (`UILaunchScreen` in `Config/Info.plist`), so the app opens without a white frame
/// and the logo starts turning where it stood.
struct LaunchCover: View {
    var body: some View {
        TicketSpinner(size: 112, on: .brand)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(role: .bgBrand, in: .gym))
            // Centred on the whole screen, as the system's launch screen centres its image.
            .ignoresSafeArea()
            .accessibilityIdentifier("launch.cover")
    }
}
