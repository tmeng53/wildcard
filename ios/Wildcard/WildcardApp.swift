import AccountDomain
import AccountUI
import CharacterEditorUI
import CheckInDomain
import CheckInUI
import Contracts
import DesignSystemUI
import FeedDomain
import FeedUI
import Foundation
import MeDomain
import MeUI
import OnboardingUI
import ScheduleDomain
import ScheduleUI
import SquadDomain
import SquadUI
import SwiftUI

/// The app target only wires packages together. With a backend (the build names one, or a Debug
/// build launched with `-local-backend`) it follows the account: sign-up until the member is in a
/// squad, then 今天 under the tab bar. Without one it opens on 今天 backed by an in-memory squad
/// and member, as UI tests do; there `-onboarding` opens sign-up first, which hands over to the
/// tabs once its 上场 has played. `-styleguide` opens the design system's style guide,
/// `-character-editor` the character editor and `-scene-pick` the scene pick instead. After the
/// first check-in it asks for notifications; a tapped one brings the member back to 今天 with the
/// home loaded again.
@main
struct WildcardApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var today: TodayModel
    @State private var schedule: ScheduleModel
    @State private var feed: FeedModel
    @State private var tab: MainTabs.Tab = LaunchOptions.firstTab
    @State private var profile: MeModel
    @State private var squad: SquadSettingsModel
    @State private var editor = CharacterEditorDemo.model()
    @State private var signUp: SignUpModel?
    @State private var app: AppModel?

    // An init, not property initializers: those run outside the main actor, and the post
    // callback and the models are the main actor's.
    init() {
        // The two screens' samples share the member and the squad, so my post opens in 动态.
        let (member, squad) = (MemberID(UUID()), SquadID(UUID()))
        _today = State(
            initialValue: TodayModel(
                store: TodayStore(
                    backend: InMemoryCheckInBackend.sampleSquad(
                        now: LaunchOptions.now(), size: LaunchOptions.squadSize, member: member, squad: squad,
                        patted: LaunchOptions.pattedMe),
                    outbox: InMemoryOutbox(),
                    now: LaunchOptions.now, newID: { UUID() }),
                writer: LaunchOptions.disclaimerWriter,
                photoSource: LaunchOptions.photoSource,
                scene: LaunchOptions.scene,
                now: LaunchOptions.now,
                defaults: LaunchOptions.todayDefaults,
                posted: Self.askForNotifications))
        _profile = State(
            initialValue: MeModel(
                service: InMemoryMeService.sample(failsSaving: LaunchOptions.meFailsSaving),
                // The in-memory member has no Apple account to confirm with and nothing to sign out of.
                confirm: { .signedInSession }, signOut: {}))
        _squad = State(
            initialValue: SquadSettingsModel(
                service: InMemorySquadSettingsService.sample(
                    seat: LaunchOptions.squadSeat, longNames: LaunchOptions.longNames)))
        _schedule = State(
            initialValue: ScheduleModel(
                store: ScheduleStore(
                    backend: InMemoryScheduleBackend.sample(now: LaunchOptions.scheduleNow()),
                    now: LaunchOptions.scheduleNow),
                photos: LaunchOptions.posterSaver))
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
        _feed = State(initialValue: Self.feed(viewer: member, squad: squad))
    }

    /// 动态 on the sample squad's week, or with no posts at all (`-uitest-empty-feed`).
    private static func feed(viewer: MemberID, squad: SquadID) -> FeedModel {
        let zone = TimeZone.current
        let source =
            LaunchOptions.showsEmptyFeed
            ? InMemoryFeedSource(viewer: viewer, posts: [], characters: [:])
            : InMemoryFeedSource.sample(
                viewer: viewer, squad: squad, now: LaunchOptions.now(), zone: zone,
                photos: InMemoryFeedSource.renderSamplePhotos())
        let store = FeedStore(
            source: source, squad: squad, viewer: viewer, today: { LocalDay(at: LaunchOptions.now(), in: zone) },
            now: { Timestamp(LaunchOptions.now()) })
        return FeedModel(store: store, viewer: viewer, now: LaunchOptions.now)
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
            } else if ScenePickDemo.isOn {
                ScenePickDemoView()
            } else if let signUp, signUp.finished == nil {
                SignUpView(model: signUp, privacyPolicy: PolicyPages.privacyPolicy, terms: PolicyPages.terms) {
                    StandInSignIn { signUp.signedIn(name: nil) }
                }
            } else if LaunchOptions.showsStyleGuide {
                StyleGuideView()
            } else if let app {
                AppRoot(app: app, tab: $tab, delegate: delegate)
            } else {
                MainTabs(today: today, profile: profile, schedule: schedule, feed: feed, squad: squad, selection: $tab)
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
                ProgressView()
            case .signUp(let signUp):
                SignUpView(model: signUp, privacyPolicy: PolicyPages.privacyPolicy, terms: PolicyPages.terms) {
                    SignInButton(app: app, signUp: signUp)
                }
                .onChange(of: signUp.finished) { _, finished in
                    if finished != nil { Task { await app.finishSignUp() } }
                }
            case .tabs(let today, let profile, let feed, let squad):
                // 出赛表 shows its placeholder here until its API adapter lands.
                MainTabs(today: today, profile: profile, schedule: nil, feed: feed, squad: squad, selection: $tab) {
                    Task { await app.leftSquad() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await app.run() }
        .onAppear {
            delegate.opened = { [app, $tab] in
                $tab.wrappedValue = .today
                Task { await app.reloadToday() }
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
