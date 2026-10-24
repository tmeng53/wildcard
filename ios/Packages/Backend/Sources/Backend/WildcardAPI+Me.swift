import Foundation

// The member's own settings and records beyond the profile: lifetime counts, the push switch,
// the AI consent and deleting the account.
extension WildcardAPI {
    /// Everything the member ever checked in, by kind.
    public func checkInTotals() async throws(APIError) -> CheckInTotals {
        let totals = try await call { try await client.getMyCheckInTotals().ok.body.json }
        return CheckInTotals(
            trainedDays: totals.trainedDays, healthyMeals: totals.healthyMeals, cheatMeals: totals.cheatMeals,
            disclaimers: totals.disclaimers)
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
}
