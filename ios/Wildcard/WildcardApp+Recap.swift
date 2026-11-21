import CheckInUI
import Contracts
import MeDomain
import RecapUI
import SwiftUI

extension WildcardApp {
    /// The sample squad's story, as the in-memory squad has no awards of its own; a scene picked on
    /// its last page puts 今天 there.
    static func sampleRecap(today: TodayModel, profile: MeModel) -> RecapShelf {
        RecapShelf(
            service: RecapSample.Service(),
            squad: { RecapSample.squad(today: LocalDay(at: LaunchOptions.now(), in: .current)) },
            seen: .onlyThisLaunch(),
            titles: { AppModel.titleWearing(profile) },
            scenePicker: { _ in
                LaunchOptions.recapPicker ? RecapSample.scenePicker(winter: LaunchOptions.recapWinter) : nil
            },
            scenePicked: { scene in today.scene = scene })
    }
}
