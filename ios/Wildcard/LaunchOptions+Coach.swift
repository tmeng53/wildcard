import Foundation
import SquadDomain
import SquadUI

extension LaunchOptions {
    /// The coach's cards on the sample squad: the sample deck, or with `-uitest-coach-seen`
    /// everything seen already, in 以前.
    static var coachCards: any CoachCardSource {
        InMemoryCoachCardSource.sample(
            now: now(), empty: ProcessInfo.processInfo.arguments.contains("-uitest-coach-seen"))
    }
}
