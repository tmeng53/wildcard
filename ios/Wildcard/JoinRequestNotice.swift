import Contracts
import Foundation

/// Which captain's no this phone has shown, so 申请没有通过 opens the app once for each; after it
/// the member is simply in no squad, as before they asked.
enum DeclineNotice {
    private static let key = "shownDeclinedJoinRequest"

    /// Whether 申请没有通过 for this request has shown on this phone.
    @MainActor static func wasShown(_ request: JoinRequestID) -> Bool {
        UserDefaults.standard.string(forKey: key) == request.description
    }

    @MainActor static func shown(_ request: JoinRequestID) {
        UserDefaults.standard.set(request.description, forKey: key)
    }
}

extension JoinRequest {
    /// A request sign-up still has to show as the app opens: one waiting for the captain, or a no
    /// this phone hasn't shown.
    @MainActor var isStillToShow: Bool {
        switch status {
        case .waiting: true
        case .declined: !DeclineNotice.wasShown(id)
        case .approved, .over: false
        }
    }
}

extension LaunchOptions {
    /// On the sample squad, `-onboarding-ask`: its captain lets members in (入队需要审核), so
    /// 加入小队 is 申请加入 and sign-up ends on 等队长同意.
    static var asksCaptain: Bool {
        ProcessInfo.processInfo.arguments.contains("-onboarding-ask")
    }
}
