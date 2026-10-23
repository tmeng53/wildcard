#if canImport(AuthenticationServices) && canImport(UIKit)
import AccountDomain
import AuthenticationServices
import UIKit

/// Asks the signed-in member to confirm with Apple again, for a step as final as deleting the
/// account, and hands back the fresh authorization code the API revokes the app's Apple tokens
/// with. Apple shows its own sheet; nothing is asked for but the confirmation.
@MainActor
public enum AppleConfirmation {
    public static func authorizationCode() async throws(AccountError) -> String {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        let result = await withCheckedContinuation { continuation in
            let delegate = Delegate { continuation.resume(returning: $0) }
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = delegate
            controller.presentationContextProvider = delegate
            // The controller holds its delegate weakly; keep it until Apple answers.
            delegate.controller = controller
            delegate.retainSelf = delegate
            controller.performRequests()
        }
        return try result.get()
    }

    // Apple calls these on the main thread.
    @MainActor
    private final class Delegate: NSObject, @preconcurrency ASAuthorizationControllerDelegate,
        @preconcurrency ASAuthorizationControllerPresentationContextProviding
    {
        var controller: ASAuthorizationController?
        var retainSelf: Delegate?
        private let finish: (Result<String, AccountError>) -> Void

        init(finish: @escaping (Result<String, AccountError>) -> Void) {
            self.finish = finish
        }

        func authorizationController(
            controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization
        ) {
            guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
                let data = apple.authorizationCode, let code = String(data: data, encoding: .utf8)
            else { return done(.failure(.credentialRejected)) }
            done(.success(code))
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
            if let error = error as? ASAuthorizationError, error.code == .canceled {
                done(.failure(.canceled))
            } else {
                done(.failure(.unavailable))
            }
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }

        private func done(_ result: Result<String, AccountError>) {
            finish(result)
            (controller, retainSelf) = (nil, nil)
        }
    }
}
#endif
