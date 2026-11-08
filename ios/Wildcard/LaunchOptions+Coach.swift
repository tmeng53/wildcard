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

    /// `-uitest-challenge`: I accepted 毛头's challenge for today (拉伸 5 分钟), not yet done, so
    /// 我的一周 shows it with 我完成了.
    static var challenge: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-challenge")
    }
}
