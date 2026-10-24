#if canImport(AuthenticationServices) && canImport(UIKit)
import AccountDomain
import AuthenticationServices
import UIKit

/// One request to Sign in with Apple: Apple shows its own sheet over the key window, and the
/// answer comes back here, what its Apple ID credential carries or why there is none.
@MainActor
enum AppleAuthorization {
    /// The parts of Apple's credential the app reads.
    struct Answer: Sendable {
        let identityToken: Data?
        let authorizationCode: Data?
        let fullName: PersonNameComponents?
    }

    static func perform(_ request: ASAuthorizationAppleIDRequest) async -> Result<Answer, AccountError> {
        await withCheckedContinuation { continuation in
            let delegate = Delegate { continuation.resume(returning: $0) }
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = delegate
            controller.presentationContextProvider = delegate
            // The controller holds its delegate weakly; keep it until Apple answers.
            delegate.controller = controller
            delegate.retainSelf = delegate
            controller.performRequests()
        }
    }

    // Apple calls these on the main thread.
    @MainActor
    private final class Delegate: NSObject, @preconcurrency ASAuthorizationControllerDelegate,
        @preconcurrency ASAuthorizationControllerPresentationContextProviding
    {
        var controller: ASAuthorizationController?
        var retainSelf: Delegate?
        private let finish: (Result<Answer, AccountError>) -> Void

        init(finish: @escaping (Result<Answer, AccountError>) -> Void) {
            self.finish = finish
        }

        func authorizationController(
            controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization
        ) {
            guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential else {
                return done(.failure(.credentialRejected))
            }
            done(
                .success(
                    Answer(
                        identityToken: apple.identityToken, authorizationCode: apple.authorizationCode,
                        fullName: apple.fullName)))
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

        private func done(_ result: Result<Answer, AccountError>) {
            finish(result)
            (controller, retainSelf) = (nil, nil)
        }
    }
}
#endif
