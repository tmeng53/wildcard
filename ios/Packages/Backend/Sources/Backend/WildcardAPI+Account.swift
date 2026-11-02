import AccountDomain
import Contracts
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Calling with the app's own sign-in.
extension WildcardAPI {
    /// Calls with the account's tokens, and signs the account out when the API refuses a renewed
    /// one, so screens following `AccountSession.states()` see the member signed out (a session
    /// signed in while that call was on its way stays).
    ///
    /// Given `member`, it calls only while they are signed in, and answers `signedOut` once
    /// someone else is: for work kept for one member, such as their outbox, which must never go
    /// out under the next account signed in on the device.
    public init(
        url: URL, account: AccountSession, member: MemberID? = nil, language: LanguageTag? = nil,
        http: URLSession = .wildcard
    ) {
        self.init(
            url: url,
            accessToken: { rejected async throws(AccountError) in
                try await account.accessToken(for: member, rejected: rejected)
            },
            refused: { token in try? await account.signOut(ifCurrent: token) },
            language: language, http: http)
    }
}
