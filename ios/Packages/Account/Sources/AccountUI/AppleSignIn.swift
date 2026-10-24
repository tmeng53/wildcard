#if canImport(AuthenticationServices) && canImport(UIKit)
import AccountDomain
import AuthenticationServices

/// What Sign in with Apple handed back.
public struct AppleSignIn: Sendable, Equatable {
    public let credential: Credential
    /// The name the member shares with us. Apple sends it on the first sign-in only, so the
    /// sign-up flow takes it from here or never gets it.
    public let name: PersonNameComponents?

    /// Signs in with Apple, asking for the member's name and email, from the app's own 通过 Apple
    /// 继续 button: Apple's drawn button speaks the language the app started in, not one picked
    /// in the app since. The email lands on the Supabase Auth user, never in our tables (a member
    /// is keyed by the provider's user id); it may be Apple's private relay address, and Apple
    /// sends it on the first authorization only, so an account made before we asked for it has
    /// none.
    @MainActor
    public static func authorize() async -> Result<AppleSignIn, AccountError> {
        // A fresh nonce for every attempt: a token is good for one sign-in.
        let nonce = AppleNonce.random()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = nonce.hashed
        return await AppleAuthorization.perform(request).flatMap { apple in
            guard let data = apple.identityToken, let token = String(data: data, encoding: .utf8) else {
                return .failure(.credentialRejected)
            }
            return .success(
                AppleSignIn(credential: .apple(identityToken: token, nonce: nonce.raw), name: apple.fullName))
        }
    }
}
#endif
