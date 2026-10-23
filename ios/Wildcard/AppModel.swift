import AccountDomain
import AccountUI
import Backend
import CheckInDomain
import CheckInUI
import Contracts
import Foundation
import MeDomain
import Observation
import OnboardingUI

/// The app on the real backend: who is signed in decides between sign-up and the tabs. A member
/// signed out, or signed in with no squad yet, goes through sign-up; one with a squad opens on
/// 今天. Signing out stops the phone's pushes and deletes what the device kept for the member.
@MainActor @Observable
final class AppModel {
    enum Screen {
        /// Reading the stored session, and the member's home once signed in.
        case starting
        case signUp(SignUpModel)
        case tabs(today: TodayModel, profile: MeModel)
    }

    private(set) var screen = Screen.starting

    @ObservationIgnored private let account: AccountSession
    @ObservationIgnored private let api: WildcardAPI
    /// Where the home's copy and the posts still to go out are kept.
    @ObservationIgnored private let directory: URL
    /// How a member confirms deleting their account: with Apple, or for a Debug test member,
    /// with the session alone.
    @ObservationIgnored private let confirmDeletion: @MainActor () async throws(MeError) -> DeletionConfirmation
    /// Called after each check-in lands; the app asks for notifications after the first.
    @ObservationIgnored private let posted: @MainActor () -> Void

    init(
        config: AppConfig, usesApple: Bool = true, posted: @escaping @MainActor () -> Void
    ) {
        account = AccountSession(
            provider: SupabaseAuth(url: config.authURL, publishableKey: config.authPublishableKey),
            store: KeychainSessionStore(), now: { Date() })
        api = WildcardAPI(url: config.apiURL, account: account)
        directory = URL.applicationSupportDirectory.appending(path: "Home", directoryHint: .isDirectory)
        self.posted = posted
        if usesApple {
            confirmDeletion = { () async throws(MeError) -> DeletionConfirmation in
                do throws(AccountError) {
                    return .apple(authorizationCode: try await AppleConfirmation.authorizationCode())
                } catch .canceled {
                    throw .confirmationCanceled
                } catch {
                    throw .confirmationFailed
                }
            }
        } else {
            confirmDeletion = { () async throws(MeError) -> DeletionConfirmation in .signedInSession }
        }
    }

    /// Follows the account for as long as the app runs: the first state picks the first screen,
    /// and signing out, from here or because the session ended, returns to the open screen.
    func run() async {
        for await state in await account.states() {
            switch state {
            case .signedOut: await signedOut()
            case .signedIn:
                await registerForPush()
                if case .starting = screen { await openHome() }
            }
        }
    }

    /// Sign in with Apple came back on the open screen.
    func signIn(_ result: Result<AppleSignIn, AccountError>, from signUp: SignUpModel) async {
        switch result {
        case .success(let apple): await signIn(with: apple.credential, name: apple.name?.givenName, from: signUp)
        case .failure(.canceled): return
        case .failure: signUp.signInFailed()
        }
    }

    /// Signs in and carries on: into sign-up's next step, or straight to 今天 for a member who
    /// already has a squad, such as on a new phone.
    func signIn(with credential: Credential, name: String?, from signUp: SignUpModel) async {
        do {
            _ = try await account.signIn(with: credential)
        } catch {
            signUp.signInFailed()
            return
        }
        await openHome(continuing: signUp, name: name)
    }

    /// 上场 has played: the squad's home takes over.
    func finishSignUp() async {
        await openHome()
    }

    /// A tapped notification: back on 今天 with the home loaded again.
    func reloadToday() async {
        if case .tabs(let today, _) = screen { await today.load() }
    }

    func signOut() async {
        try? await Push.registration.signingOut()
        try? await account.signOut()
    }

    /// Loads the member's home and opens 今天 on it, or sign-up when they are in no squad.
    private func openHome(continuing signUp: SignUpModel? = nil, name: String? = nil) async {
        let store = TodayStore(
            backend: APICheckInBackend(api: api, directory: directory), outbox: DeviceOutbox(directory: directory),
            now: { Date() }, newID: { UUID() })
        await store.load()
        switch store.phase {
        case .noSquad:
            // Consent is the account's: a member who agreed before, and left their squad since,
            // isn't asked again. Not knowing asks, and agreeing again is safe.
            let agreed = (try? await api.hasAgreedToAI()) ?? false
            let model = (agreed ? nil : signUp) ?? newSignUp(hasAgreedToAI: agreed)
            model.signedIn(name: name)
            screen = .signUp(model)
        case .signedOut:
            await signedOut()
        case .offline where store.home == nil:
            // Nothing kept on the phone to show, so it isn't known yet whether the member has a
            // squad. Rather than open an empty 今天: after signing in on the open screen, say it
            // didn't work so they can try again; at launch, wait and try again.
            if let signUp {
                signUp.signInFailed()
                return
            }
            screen = .starting
            try? await Task.sleep(for: .seconds(3))
            await openHome()
        case .loading, .current, .offline:
            screen = .tabs(
                today: TodayModel(
                    store: store, writer: APIDisclaimerWriter(api: api, fallback: DiceDisclaimerWriter()),
                    posted: posted),
                profile: MeModel(
                    service: APIMeService(api: api, beforeDeleting: { try? await Push.registration.signingOut() }),
                    confirm: confirmDeletion, signOut: { [weak self] in await self?.signOut() }))
        }
    }

    private func registerForPush() async {
        try? await Push.registration.signedIn(APIDeviceRegistry(api: api))
    }

    private func signedOut() async {
        APICheckInBackend(api: api, directory: directory).forget()
        await DeviceOutbox(directory: directory).forget()
        if case .signUp(let model) = screen, model.step == .welcome { return }
        screen = .signUp(newSignUp(hasAgreedToAI: false))
    }

    private func newSignUp(hasAgreedToAI: Bool) -> SignUpModel {
        SignUpModel(
            service: APISignUpService(api: api), invite: nil, nickname: "", now: Date(), hasAgreedToAI: hasAgreedToAI)
    }
}
