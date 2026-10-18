import DesignSystemUI
import SwiftUI

/// The app target only wires packages together. Until the first feature screen lands, it
/// opens on the design system's style guide.
@main
struct WildcardApp: App {
    var body: some Scene {
        WindowGroup {
            StyleGuideView()
        }
    }
}
