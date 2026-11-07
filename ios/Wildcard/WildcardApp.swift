import AccountDomain
import AccountUI
import Backend
import CharacterEditorUI
import CheckInDomain
import CheckInUI
import Combine
import Contracts
import DailyPushDomain
import DesignSystem
import DesignSystemUI
import FeedDomain
import FeedUI
import Foundation
import HealthUI
import MeDomain
import MeUI
import NotificationsUI
import OnboardingUI
import RecapUI
import ScheduleDomain
import ScheduleUI
import SportsUI
import SquadDomain
import SquadUI
import SwiftUI

/// The app's entry point: the language first, then the app.
@main
enum Launch {
    @MainActor static func main() {
        DefaultLanguage.apply()
        WildcardApp.main()
    }
}

/// The app target only wires packages together. With a backend (the build names one, or a Debug
/// build launched with `-local-backend`) it follows the account: sign-up until the member is in a
/// squad, then 今天 under the tab bar. Without one it opens on 今天 backed by an in-memory squad
/// and member, as UI tests do; there `-onboarding` opens sign-up first, which hands over to the
/// tabs once its 上场 has played. `-styleguide` opens the design system's style guide,
/// `-character-editor` the character editor, `-loading` the launch page, `-recap` the 战报's tile and
/// sample story and `-daily-push` the 6pm push's view instead. After the first check-in it asks
/// for notifications; a tapped one brings the member back to 今天 with the home loaded again, or,
/// for an awards push, to 动态, where the 战报's tile is, or goes where the 6pm push's view asked.
/// `Launch` starts it.
struct WildcardApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var today: TodayModel
    @State private var schedule: ScheduleModel
    @State private var feed: FeedModel
    /// The sample member's own posts, from the sample squad's 动态.
    @State private var myPosts: any MyPostsSource
    @State private var tab: MainTabs.Tab = LaunchOptions.firstTab
    /// Where a tapped push goes, kept until the tabs open it.
    @State private var pushDestination: AppDestination?
    @State private var profile: MeModel
    @State private var squad: SquadSettingsModel
    @State private var recap: RecapShelf
    @State private var editor: CharacterEditorModel?
    @State private var signUp: SignUpModel?
    /// Whether `-onboarding`'s sign-up has handed over to the tabs: after it ends, and for whoever
    /// made their squad only once the squad is dropping onto the scene they picked, so the
    /// tabs never show the squad's old scene first.
    @State private var signedUp = false
    /// Signing in on `-onboarding`'s open screen, which `-slow-sign-in` makes last long enough
    /// for the loader to show.
    @State private var isSigningIn = false
    @State private var app: AppModel?
    /// The language the app speaks; a pick in the app draws everything again in it.
    @State private var language = AppLanguage.current

    // An init, not property initializers: those run outside the main actor, and the post
    // callback and the models are the main actor's.
    init() {
        CrashReports.start()
        // The 6pm push's view speaks the app's language, picked in the app or iOS Settings.
        AppLanguage.current.share(in: AppGroup.defaults)
        // The catalog this build ships with; with a backend, `AppModel` shows the kept or newer one.
        AppModel.show(CatalogClient.bundled)
        // Only now: the editor's street is the catalog's starter street, which `show` just put out.
        _editor = State(initialValue: CharacterEditorDemo.model())
        LaunchOptions.forgetTodayStateIfAsked()
        // The two screens' samples share the member and the squad, so my post opens in 动态.
        let (member, squad) = (MemberID(UUID()), SquadID(UUID()))
        let today = TodayModel(
            store: TodayStore(
                backend: InMemoryCheckInBackend.sampleSquad(
                    now: LaunchOptions.now(), size: LaunchOptions.squadSize, member: member, squad: squad,
                    patted: LaunchOptions.pattedMe, coach: LaunchOptions.sidelineCoach,
                    coachNote: LaunchOptions.coachNote, together: LaunchOptions.together, meals: LaunchOptions.meals),
                outbox: InMemoryOutbox(), unlocks: SampleUnlockLedger(unlocks: LaunchOptions.unlocked),
                now: LaunchOptions.now, newID: { UUID() }),
            writer: LaunchOptions.disclaimerWriter,
            photoSource: LaunchOptions.photoSource,
            scene: LaunchOptions.scene,
            health: Self.sampleHealth(),
            now: LaunchOptions.now,
            defaults: LaunchOptions.todayDefaults,
            bubbleHold: LaunchOptions.bubbleHold,
            celebratesTogether: LaunchOptions.together != nil,
            posted: Self.askForNotifications)
        _today = State(initialValue: today)
        _profile = State(initialValue: Self.sampleProfile())
        _squad = State(
            initialValue: SquadSettingsModel(
                service: InMemorySquadSettingsService.sample(
                    seat: LaunchOptions.squadSeat, longNames: LaunchOptions.longNames)))
        _schedule = State(initialValue: Self.sampleSchedule())
        _recap = State(initialValue: Self.sampleRecap(today: today))
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
                    service: InMemorySignUpService.sampleSquad(), nickname: "",
                    now: LaunchOptions.signUpTime))
        }
        let feedSource = Self.feedSource(viewer: member, squad: squad)
        _feed = State(initialValue: Self.feed(viewer: member, squad: squad, source: feedSource))
        _myPosts = State(initialValue: feedSource)
    }

    /// The sample member's 出赛表.
    /// Apple Health on the sample squad: the sample day once connected (`-health-sample`).
    private static func sampleHealth() -> HealthConnection {
        HealthConnection(
            library: SampleHealthLibrary(connected: LaunchOptions.healthSample, endingNear: LaunchOptions.now()),
            defaults: LaunchOptions.todayDefaults, now: LaunchOptions.now)
    }

    private static func sampleSchedule() -> ScheduleModel {
        ScheduleModel(
            store: ScheduleStore(
                backend: InMemoryScheduleBackend.sample(now: LaunchOptions.scheduleNow()),
                now: LaunchOptions.scheduleNow),
            templateOfferHold: LaunchOptions.templateOfferHold)
    }

    /// The sample member for 我. The in-memory member has no Apple account to confirm with and
    /// nothing to sign out of.
    private static func sampleProfile() -> MeModel {
        let service = InMemoryMeService.sample(
            failsSaving: LaunchOptions.meFailsSaving, unlocks: LaunchOptions.unlocked, stock: LaunchOptions.stock)
        // What the server would work out while the app was away, for the test that 商店街 reads it again.
        if let later = LaunchOptions.stockOnReturn {
            _ = NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
            ) { _ in Task { await service.set(stock: later) } }
        }
        return MeModel(service: service, confirm: { .signedInSession }, signOut: {})
    }

    /// The sample squad's story, as the in-memory squad has no awards of its own; a scene picked on
    /// its last page puts 今天 there.
    private static func sampleRecap(today: TodayModel) -> RecapShelf {
        RecapShelf(
            service: RecapSample.Service(),
            squad: { RecapSample.squad(today: LocalDay(at: LaunchOptions.now(), in: .current)) },
            seen: .onlyThisLaunch(),
            scenePicker: { _ in LaunchOptions.recapPicker ? RecapSample.scenePicker() : nil },
            scenePicked: { scene in today.scene = scene })
    }

    /// The sample squad's week, no posts at all (`-uitest-empty-feed`) or none that can be read
    /// (`-uitest-offline-feed`).
    private static func feedSource(viewer: MemberID, squad: SquadID) -> InMemoryFeedSource {
        LaunchOptions.showsEmptyFeed || LaunchOptions.feedIsOffline
            ? InMemoryFeedSource(viewer: viewer, posts: [], characters: [:], offline: LaunchOptions.feedIsOffline)
            : InMemoryFeedSource.sample(
                viewer: viewer, squad: squad, now: LaunchOptions.now(), zone: .current,
                photos: samplePhotos(), coach: LaunchOptions.sidelineCoach)
    }

    /// The sample posts' photos, drawn only when the sample squad can show: with a backend the
    /// tabs are `AppRoot`'s, and drawing them would hold the launch on the main actor for nothing.
    private static func samplePhotos() -> [String: Data] {
        AppConfig.current == nil ? InMemoryFeedSource.renderSamplePhotos() : [:]
    }

    /// 动态 on the sample squad.
    private static func feed(viewer: MemberID, squad: SquadID, source: InMemoryFeedSource) -> FeedModel {
        let zone = TimeZone.current
        let store = FeedStore(
            source: source, squad: squad, viewer: viewer, today: { LocalDay(at: LaunchOptions.now(), in: zone) },
            now: { Timestamp(LaunchOptions.now()) }, newCommentID: { CommentID(UUID()) })
        let coach = FeedCoach(source: source, squad: squad, now: { LaunchOptions.now() })
        return FeedModel(
            store: store, viewer: viewer, editor: InMemoryPostEditor(source: source), coach: coach,
            now: LaunchOptions.now)
    }

    /// A tapped notification: 今天, or where the 6pm push's view asked to go (动态, or 今天 with
    /// the check-in kinds open).
    static func open(_ destination: PushDestination?, today: TodayModel, tab: Binding<MainTabs.Tab>) {
        switch destination {
        case .feed:
            tab.wrappedValue = .feed
        case .checkIn:
            tab.wrappedValue = .today
            today.openCheckIn()
        case nil:
            tab.wrappedValue = .today
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
            root
                .environment(\.locale, language.locale)
                .id(language)
                .onReceive(NotificationCenter.default.publisher(for: AppLanguage.didChange)) { _ in
                    language = AppLanguage.current
                    language.share(in: AppGroup.defaults)
                }
                .dismissesKeyboardOnTapOutside()
        }
    }

    @ViewBuilder private var root: some View {
        if let editor {
            CharacterEditorView(
                model: editor, context: CharacterEditorDemo.context, issued: .now, onBack: {}, onDone: { _ in })
        } else if let signUp, !signedUp {
            SignUpView(model: signUp, privacyPolicy: PolicyPages.privacyPolicy, terms: PolicyPages.terms) {
                ContinueWithApple {
                    if let wait = LaunchOptions.signInWait {
                        Task {
                            isSigningIn = true
                            try? await Task.sleep(for: .seconds(wait))
                            signUp.signedIn(name: nil)
                            isSigningIn = false
                        }
                    } else {
                        signUp.signedIn(name: nil)
                    }
                }
            } tabs: { showsBar, content in
                MainTabs.entranceTabs(showsBar: showsBar, content: content)
            }
            // As on the real backend's open screen.
            .loadingCover(isSigningIn) { LaunchCover() }
            .onChange(of: signUp.finished) { _, finished in
                guard finished != nil else { return }
                Task {
                    if let scene = signUp.landing { await today.dropIn(on: scene, coveredAt: .now) }
                    signedUp = true
                }
            }
        } else if LaunchOptions.showsStyleGuide {
            StyleGuideView()
        } else if LaunchOptions.showsLoading {
            LaunchCover()
        } else if LaunchOptions.showsRecap {
            RecapDemo()
        } else if let day = LaunchOptions.dailyPush {
            DailyPushPreview(day: day, now: LaunchOptions.now())
        } else if let app {
            AppRoot(app: app, tab: $tab, delegate: delegate)
        } else {
            MainTabs(
                today: today, profile: profile, schedule: schedule, feed: feed, squad: squad, recap: recap,
                myPosts: myPosts, notices: LaunchOptions.notices, selection: $tab, destination: $pushDestination
            )
            .onAppear {
                // As on the real backend: a push opens where its notice in 通知 goes, unless the
                // 6pm push's view asked for 动态 or 打卡; any other push opens 今天.
                delegate.opened = { [delegate, today, $tab, $pushDestination] opened in
                    switch opened {
                    case .open(let place) where !delegate.hasDestination:
                        $pushDestination.wrappedValue = place
                    case .open, .other:
                        Self.open(delegate.takeDestination(), today: today, tab: $tab)
                        Task { await today.load() }
                    }
                }
                if let destination = delegate.takeDestination() {
                    Self.open(destination, today: today, tab: $tab)
                }
            }
            .task { await Self.moveSampleSquad(today: today) }
        }
    }

    /// `-uitest-scene-moved track`: once the sample home is up, its first teammate moves the
    /// squad there, as a real move is told: the drop, then the notice. `-uitest-takeover trot`
    /// stands a takeover scene in for the squad's, with its opening.
    private static func moveSampleSquad(today: TodayModel) async {
        if let takeover = LaunchOptions.takeover {
            await today.load()
            await today.land(on: today.scene, move: nil, takeover: takeover)
        }
        guard let scene = LaunchOptions.sceneMoved else { return }
        await today.load()
        let picker = today.home.flatMap { home in home.squad.members.first { $0 != home.member } }
        await today.land(on: scene, move: SceneMove(scene: scene, picker: picker))
    }
}
