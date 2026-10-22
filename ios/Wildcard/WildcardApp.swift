import CharacterEditorUI
import CheckInDomain
import CheckInUI
import DesignSystemUI
import Foundation
import MeDomain
import MeUI
import OnboardingUI
import ScheduleDomain
import ScheduleUI
import SwiftUI

/// The app target only wires packages together. It opens on 今天 under the tab bar, backed by an
/// in-memory squad and member until sign-in lands; `-onboarding` opens sign-up first, which hands
/// over to the tabs once its 上场 has played; `-styleguide` opens the design system's style guide and
/// `-character-editor` the character editor instead. After the first check-in it asks for
/// notifications; a tapped one brings the member back to 今天 with the home loaded again.
@main
struct WildcardApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var today: TodayModel
    @State private var schedule: ScheduleModel
    @State private var tab: MainTabs.Tab = LaunchOptions.firstTab
    @State private var profile: MeModel
    @State private var editor = CharacterEditorDemo.model()
    @State private var signUp: SignUpModel?

    // An init, not property initializers: those run outside the main actor, and the post
    // callback and the models are the main actor's.
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
        _schedule = State(
            initialValue: ScheduleModel(
                store: ScheduleStore(
                    backend: InMemoryScheduleBackend.sample(now: LaunchOptions.scheduleNow()),
                    now: LaunchOptions.scheduleNow),
                photos: LaunchOptions.posterSaver))
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
            } else {
                MainTabs(today: today, profile: profile, schedule: schedule, selection: $tab)
                    .onAppear {
                        delegate.opened = { [today, $tab] in
                            $tab.wrappedValue = .today
                            Task { await today.load() }
                        }
                    }
            }
        }
    }
}
