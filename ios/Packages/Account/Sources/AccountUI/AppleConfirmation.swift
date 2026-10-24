#if canImport(AuthenticationServices) && canImport(UIKit)
import AccountDomain
import AuthenticationServices

/// Asks the signed-in member to confirm with Apple again, for a step as final as deleting the
/// account, and hands back the fresh authorization code the API revokes the app's Apple tokens
/// with. Apple shows its own sheet; nothing is asked for but the confirmation.
@MainActor
public enum AppleConfirmation {
    public static func authorizationCode() async throws(AccountError) -> String {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        let apple = try await AppleAuthorization.perform(request).get()
        guard let data = apple.authorizationCode, let code = String(data: data, encoding: .utf8) else {
            throw .credentialRejected
        }
        return code
    }
}
#endif
