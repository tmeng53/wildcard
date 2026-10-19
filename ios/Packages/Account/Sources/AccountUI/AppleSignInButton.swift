#if canImport(AuthenticationServices) && canImport(SwiftUI)
import AccountDomain
import AuthenticationServices
import SwiftUI

/// What Sign in with Apple handed back.
public struct AppleSignIn: Sendable, Equatable {
    public let credential: Credential
    /// The name the member shares with us. Apple sends it on the first sign-in only, so the
    /// sign-up flow takes it from here or never gets it.
    public let name: PersonNameComponents?
}

/// Apple's own Sign in with Apple button, which App Review expects to look as Apple draws it.
/// It asks for the member's name only, never their email.
public struct AppleSignInButton: View {
    private let onCompletion: (Result<AppleSignIn, AccountError>) -> Void
    @State private var nonce = AppleNonce.random()
    @Environment(\.colorScheme) private var colorScheme

    public init(onCompletion: @escaping (Result<AppleSignIn, AccountError>) -> Void) {
        self.onCompletion = onCompletion
    }

    public var body: some View {
        SignInWithAppleButton(.signIn) { request in
            // A fresh nonce for every attempt: a token is good for one sign-in.
            nonce = AppleNonce.random()
            request.requestedScopes = [.fullName]
            request.nonce = nonce.hashed
        } onCompletion: { result in
            onCompletion(Self.signIn(from: result, nonce: nonce))
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
    }

    static func signIn(from result: Result<ASAuthorization, any Error>, nonce: AppleNonce)
        -> Result<AppleSignIn, AccountError>
    {
        switch result {
        case .success(let authorization):
            guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = apple.identityToken,
                let token = String(data: tokenData, encoding: .utf8)
            else { return .failure(.credentialRejected) }
            return .success(
                AppleSignIn(credential: .apple(identityToken: token, nonce: nonce.raw), name: apple.fullName))
        case .failure(let error as ASAuthorizationError) where error.code == .canceled:
            return .failure(.canceled)
        case .failure:
            return .failure(.unavailable)
        }
    }
}
#endif
