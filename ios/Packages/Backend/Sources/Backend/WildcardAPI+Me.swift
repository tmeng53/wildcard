import APIContract
import Contracts
import Foundation

// The member's own settings and records beyond the profile: lifetime counts, the push switch,
// the AI consent and deleting the account.
extension WildcardAPI {
    /// Everything the member ever checked in, by kind.
    public func checkInTotals() async throws(APIError) -> CheckInTotals {
        let totals = try await call { try await client.getMyCheckInTotals().ok.body.json }
        let topSport = try read { () throws(ContractsError) in
            try totals.topSport.map { top throws(ContractsError) in
                TopSport(activity: try Activity(top), checkIns: top.checkIns)
            }
        }
        return CheckInTotals(
            trainedDays: totals.trainedDays, healthyMeals: totals.healthyMeals, cheatMeals: totals.cheatMeals,
            disclaimers: totals.disclaimers, topSport: topSport)
    }

    /// Every weekly title (周奖) the member has won, in all their squads.
    public func awardTotals() async throws(APIError) -> AwardTotals {
        let totals = try await call { try await client.getMyAwardTotals().ok.body.json }
        return AwardTotals(
            titles: totals.titles, latest: totals.latest.map { AwardTotals.Latest(title: $0.title, times: $0.times) })
    }

    /// Whether the one daily push at 6pm is on; it is until the member turns it off.
    public func dailyPushOn() async throws(APIError) -> Bool {
        try await call { try await client.getMyPushSettings().ok.body.json }.settings.dailyProgress ?? true
    }

    /// Turns the daily push on or off. Safe to repeat.
    public func setDailyPush(_ isOn: Bool) async throws(APIError) {
        _ = try await call {
            try await client.saveMyPushSettings(body: .json(.init(version: ._1, settings: .init(dailyProgress: isOn))))
                .ok
        }
    }

    /// Deletes the account and everything that is the member's, for good. `appleAuthorizationCode`,
    /// from confirming with Apple again, lets the API revoke the app's Apple tokens. Safe to repeat
    /// after a failure; signing out after is the caller's to do.
    public func deleteAccount(appleAuthorizationCode: String?) async throws(APIError) {
        _ = try await call {
            try await client.deleteMe(body: .json(.init(version: ._1, appleAuthorizationCode: appleAuthorizationCode)))
                .noContent
        }
    }

    /// Whether the member has agreed to the API's current AI consent copy.
    public func hasAgreedToAI() async throws(APIError) -> Bool {
        try await call { try await client.getMyAiConsent().ok.body.json }.current
    }

    /// Records that the member agreed to the AI consent copy the app showed. Safe to retry.
    public func agreeToAI(copyVersion: Int) async throws(APIError) {
        _ = try await call {
            try await client.putMyAiConsent(body: .json(.init(version: ._1, copyVersion: copyVersion))).ok
        }
    }
}

/// Everything a member ever checked in, by kind. Several 练了 on one day count once.
public struct CheckInTotals: Hashable, Sendable {
    public let trainedDays: Int
    public let healthyMeals: Int
    public let cheatMeals: Int
    public let disclaimers: Int
    /// The sport with the most 练了 (最常练); nil before the first.
    public let topSport: TopSport?
}

/// The sport a member logged the most 练了 for, and how many.
public struct TopSport: Hashable, Sendable {
    public let activity: Activity
    public let checkIns: Int
}

/// Every weekly title (周奖) a member has won, and the latest with how often they won it.
public struct AwardTotals: Hashable, Sendable {
    public struct Latest: Hashable, Sendable {
        public let title: String
        public let times: Int
    }

    public let titles: Int
    /// Nil before the first title.
    public let latest: Latest?
}
