import AccountDomain
import AccountUI
import CharacterEditorUI
import CheckInDomain
import CheckInUI
import Contracts
import DesignSystemUI
import Foundation
import MeDomain
import MeUI
import OnboardingUI
import RecapUI
import SwiftUI

/// The app target only wires packages together. With a backend (the build names one, or a Debug
/// build launched with `-local-backend`) it follows the account: sign-up until the member is in a
/// squad, then 今天 under the tab bar. Without one it opens on 今天 backed by an in-memory squad
/// and member, as UI tests do; there `-onboarding` opens sign-up first, which hands over to the
/// tabs once its 上场 has played. `-styleguide` opens the design system's style guide,
/// `-character-editor` the character editor and `-recap` the 战报's tile and sample story
/// instead. After the first check-in it asks for notifications; a tapped one brings the member
/// back to 今天 with the home loaded again, or opens the 战报 its awards push is about.
@main
struct WildcardApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var today: TodayModel
    @State private var tab: MainTabs.Tab = LaunchOptions.firstTab
    @State private var profile: MeModel
    @State private var recap: RecapShelf
    @State private var editor = CharacterEditorDemo.model()
    @State private var signUp: SignUpModel?
    @State private var app: AppModel?

    // An init, not property initializers: those run outside the main actor, and the post
    // callback and both models are the main actor's.
    init() {
        _today = State(
            initialValue: TodayModel(
                store: TodayStore(
                    backend: InMemoryCheckInBackend.sampleSquad(now: LaunchOptions.now()), outbox: InMemoryOutbox(),
                    now: LaunchOptions.now, newID: { UUID() }),
                writer: LaunchOptions.disclaimerWriter,
                photoSource: LaunchOptions.photoSource,
                now: LaunchOptions.now,
                posted: Self.askForNotifications))
        _profile = State(
            initialValue: MeModel(
                service: InMemoryMeService.sample(failsSaving: LaunchOptions.meFailsSaving),
                // The in-memory member has no Apple account to confirm with and nothing to sign out of.
                confirm: { .signedInSession }, signOut: {}))
        // The sample squad's story, as the in-memory squad has no awards of its own.
        _recap = State(
            initialValue: RecapShelf(
                service: RecapSample.Service(),
                squad: { RecapSample.squad(today: LocalDay(at: LaunchOptions.now(), in: .current)) }))
        #if DEBUG
        let usesApple = LaunchOptions.testMember == nil
        #else
        let usesApple = true
        #endif
        _app = State(
            initialValue: AppConfig.current.map {
                AppModel(config: $0, usesApple: usesApple, posted: Self.askForNotifications)
            })
        if LaunchOptions.showsOnboarding {
            _signUp = State(
                initialValue: SignUpModel(
                    service: InMemorySignUpService.sampleSquad(), invite: nil, nickname: "",
                    now: LaunchOptions.signUpTime))
        }
    }

    /// After a post, once the cheer has played: the first one brings up the permission prompt.
    private static func askForNotifications() {
        guard LaunchOptions.asksForNotifications else { return }
        Task {
            try? await Task.sleep(for: Push.promptDelay)
            await Push.registration.checkedIn()
        }
    }

    var body: some Scene {
        WindowGroup {
            if let editor {
                CharacterEditorView(model: editor, context: CharacterEditorDemo.context, onBack: {}, onDone: { _ in })
            } else if let signUp, signUp.finished == nil {
                SignUpView(model: signUp, privacyPolicy: PolicyPages.privacyPolicy, terms: PolicyPages.terms) {
                    StandInSignIn { signUp.signedIn(name: nil) }
                }
            } else if LaunchOptions.showsStyleGuide {
                StyleGuideView()
            } else if LaunchOptions.showsRecap {
                RecapDemo()
            } else if let app {
                AppRoot(app: app, tab: $tab, delegate: delegate)
            } else {
                MainTabs(today: today, profile: profile, recap: recap, selection: $tab)
                    .onAppear {
                        delegate.opened = { [today, $tab] _ in
                            $tab.wrappedValue = .today
                            Task { await today.load() }
                        }
                    }
            }
        }
    }
}

/// The app on the real backend: the screen its account is on.
private struct AppRoot: View {
    let app: AppModel
    @Binding var tab: MainTabs.Tab
    let delegate: AppDelegate

    var body: some View {
        // A ZStack, not a Group, so the task below starts once and outlives screen changes.
        ZStack {
            switch app.screen {
            case .starting:
                EmptyView()
            case .signUp(let signUp):
                SignUpView(model: signUp, privacyPolicy: PolicyPages.privacyPolicy, terms: PolicyPages.terms) {
                    SignInButton(app: app, signUp: signUp)
                }
                .onChange(of: signUp.finished) { _, finished in
                    if finished != nil { Task { await app.finishSignUp() } }
                }
            case .tabs(let today, let profile, let recap):
                MainTabs(today: today, profile: profile, recap: recap, selection: $tab)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await app.run() }
        .onAppear {
            delegate.opened = { [app, $tab] opened in
                switch opened {
                case .weeklyAwards(let squad, let week):
                    $tab.wrappedValue = .feed
                    Task { await app.openRecap(squad: squad, week: week) }
                case .other:
                    $tab.wrappedValue = .today
                    Task { await app.reloadToday() }
                }
            }
        }
    }
}

/// The open screen's sign-in: Sign in with Apple, or in Debug with `-test-member` a stand-in
/// that signs in as that member of local Supabase.
private struct SignInButton: View {
    let app: AppModel
    let signUp: SignUpModel

    var body: some View {
        #if DEBUG
        if let member = LaunchOptions.testMember {
            StandInSignIn {
                Task {
                    await app.signIn(
                        with: .testMember(email: member.email, password: member.password), name: nil, from: signUp)
                }
            }
        } else {
            apple
        }
        #else
        apple
        #endif
    }

    private var apple: some View {
        AppleSignInButton { result in
            Task { await app.signIn(result, from: signUp) }
        }
    }
}
