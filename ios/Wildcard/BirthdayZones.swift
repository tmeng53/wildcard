import HealthUI
import MeDomain
import SwiftUI

extension View {
    /// Hands Apple Health the birthday the member gave or forgot on 我, so the next post's heart-rate
    /// zones follow it; while 我 is still reading, the one read at launch stands.
    func placesZones(from profile: MeModel, in health: HealthConnection?) -> some View {
        onChange(of: profile.overview?.birthday) { _, birthday in
            if profile.overview != nil { health?.birthday = birthday }
        }
    }
}
