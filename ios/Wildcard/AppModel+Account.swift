import AccountDomain
import Backend
import Contracts
import MeDomain

/// Signing out, and an admin switching between their own account and their demo accounts
/// (演示账号, Tracy 2026-11-13).
extension AppModel {
    /// Where an admin's own session waits while they are on a demo account: only the app needs
    /// it, so it stays out of the app group.
    static let keptSession = "com.wildcardsquad.wildcard.kept-session"

    func signOut() async {
        try? await Push.registration.signingOut()
        try? await account.signOut()
    }

    /// 演示账号 for an admin or one of their demo accounts, on `current`; nil for everyone else.
    func demoAccounts(on current: MemberID, if member: Member?) -> DemoAccountsModel? {
        guard member?.isAdmin == true || member?.isDemo == true else { return nil }
        return DemoAccountsModel(
            service: APIDemoAccountService(api: api), current: current,
            switchTo: { [weak self] in await self?.switchToDemo($0) ?? false },
            returnHome: { [weak self] in await self?.returnFromDemo() ?? false })
    }

    /// This phone on one of the admin's demo accounts, opened like a sign-in (its home, or
    /// sign-up for a new one). False when it didn't switch, and the account it was on opens again.
    func switchToDemo(_ member: MemberID) async -> Bool {
        guard let credential = try? await api.handOff(to: member) else { return false }
        return await switchAccount { [account] () throws(AccountError) in
            try await account.switchToDemo(with: credential)
        }
    }

    /// 演示账号's 我的账号: back on the admin's own account from a demo account.
    func returnFromDemo() async -> Bool {
        await switchAccount { [account] () throws(AccountError) in try await account.returnFromDemo() }
    }

    /// Changes who is signed in on this phone. Its pushes follow the account it is on, and the
    /// account's new state opens that account's home from under the launch cover.
    private func switchAccount(_ change: () async throws(AccountError) -> MemberID) async -> Bool {
        try? await Push.registration.signingOut()
        SignUpProgress.clear()
        screen = .starting
        do {
            _ = try await change()
            return true
        } catch {
            await registerDevice()
            await openHome()
            return false
        }
    }
}
