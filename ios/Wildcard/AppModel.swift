import AccountDomain
import AccountUI
import Backend
import CheckInDomain
import CheckInUI
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import FeedUI
import Foundation
import MeDomain
import Observation
import OnboardingUI
import RecapDomain
import RecapUI
import ScenePickDomain
import ScheduleDomain
import ScheduleUI
import SportsUI
import SquadDomain

/// The app on the real backend: who is signed in decides between sign-up and the tabs. A member
/// signed out, or signed in with no squad yet, goes through sign-up; one with a squad opens on
/// 今天. Signing out stops the phone's pushes and deletes what the device kept for the member.
@MainActor @Observable
final class AppModel {
    enum Screen {
        /// Reading the stored session, and the member's home once signed in.
        case starting
        case signUp(SignUpModel)
        case tabs(
            today: TodayModel, profile: MeModel, schedule: ScheduleModel, feed: FeedModel, squad: SquadSettingsModel,
            recap: RecapShelf)
    }

    private(set) var screen = Screen.starting
    /// Whether the launch cover is up: until the first screen, with its scene, is ready.
    var isStarting: Bool {
        if case .starting = screen { return true }
        return false
    }
    /// Signing in on the open screen, until the screen after it opens.
    private(set) var isSigningIn = false
    /// Whether the tabs are up, so leaving them (signing out, deleting the account, leaving the
    /// squad) puts the next tabs back on 今天.
    var showsTabs: Bool {
        if case .tabs = screen { return true }
        return false
    }
    /// The squad 今天 is on, whose scene it reads again each time the app comes back.
    @ObservationIgnored private var homeSquad: SquadID?
    /// A home opening under the launch cover after a sign-in on the open screen, so the account's
    /// next signed-in state doesn't open it a second time.
    @ObservationIgnored private var openingUnderCover = false

    @ObservationIgnored private let account: AccountSession
    @ObservationIgnored private let api: WildcardAPI
    /// The API for one member's own home and outbox: it stops calling once someone else signs in,
    /// so posts queued for one account never go out under the next.
    @ObservationIgnored private let memberAPI: (MemberID) -> WildcardAPI
    /// Where the home's copy and the posts still to go out are kept, a folder per member, so a
    /// new account on this phone never opens on what was kept for one signed out or deleted.
    @ObservationIgnored private let folders: MemberFolders
    /// The lists the app shows that live in the database, such as every sport.
    @ObservationIgnored private let catalog: CatalogClient
    /// The squad's looks, kept for the 6pm push view.
    @ObservationIgnored private let shared = AppGroup.directory.map(SharedSquad.init)
    /// How a member confirms deleting their account: with Apple, or for a Debug test member,
    /// with the session alone.
    @ObservationIgnored private let confirmDeletion: @MainActor () async throws(MeError) -> DeletionConfirmation
    /// Called after each check-in lands; the app asks for notifications after the first.
    @ObservationIgnored private let posted: @MainActor () -> Void

    init(
        config: BackendAddress, usesApple: Bool = true, posted: @escaping @MainActor () -> Void
    ) {
        account = AccountSession(
            provider: SupabaseAuth(url: config.authURL, publishableKey: config.authPublishableKey),
            store: KeychainSessionStore(accessGroup: AppGroup.id), now: { Date() })
        api = WildcardAPI(url: config.apiURL, account: account, language: { AppLanguage.current.rawValue })
        memberAPI = { [account] member in
            WildcardAPI(
                url: config.apiURL, account: account, member: member, language: { AppLanguage.current.rawValue })
        }
        folders = MemberFolders(
            root: URL.applicationSupportDirectory.appending(path: "Home", directoryHint: .isDirectory))
        catalog = CatalogClient(
            api: api, directory: URL.applicationSupportDirectory.appending(path: "Catalog", directoryHint: .isDirectory)
        )
        Self.show(catalog.kept())
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
        Task { await refreshCatalog() }
        for await state in await account.states() {
            switch state {
            case .signedOut: await signedOut()
            case .signedIn:
                await registerForPush()
                if case .starting = screen, !openingUnderCover { await openHome() }
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
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            _ = try await account.signIn(with: credential)
        } catch {
            signUp.signInFailed()
            return
        }
        await openHome(continuing: signUp, name: name)
    }

    /// 上场 has played, or the scene the member's new squad picked has filled the screen: the
    /// squad's home takes over, and on a picked scene the member drops onto it.
    func finishSignUp(landingOn scene: SceneTheme?) async {
        SignUpProgress.clear()
        await openHome(landingOn: scene)
    }

    /// A tapped notification: back on 今天 with the home loaded again.
    func reloadToday() async {
        if case .tabs(let today, _, _, _, _, _) = screen { await today.load() }
    }

    /// A tapped awards push: 动态 reads the 战报 again, so its tile shows the new one for the
    /// member to open. Tabs not up yet read it as they open.
    func readRecapAgain() async {
        guard case .tabs(_, _, _, _, _, let recap) = screen else { return }
        await recap.refresh()
    }

    /// The member left their squad on 小队设置: sign-up's squad step, as for a member in none.
    func leftSquad() async {
        await openHome()
    }

    /// Reads the catalog again, as the app comes back to the front: a sport or dice line added on
    /// the server shows without an app update.
    func refreshCatalog() async {
        if let fresh = await catalog.refresh() { Self.show(fresh) }
    }

    /// Hands each part of the catalog to the screens that read it. Static, since `init` calls it
    /// before every property is set.
    private static func show(_ catalog: AppCatalog) {
        SportList.shared.show(catalog.sports)
        DiceLines.shared.show(catalog.diceLines)
    }

    /// Back in the app: 今天 reads the squad's scene again, which a teammate may have picked
    /// from their phone meanwhile.
    func refreshScene() async {
        guard case .tabs(let today, _, _, _, _, _) = screen else { return }
        await readScene(of: homeSquad, into: today)
    }

    func signOut() async {
        try? await Push.registration.signingOut()
        try? await account.signOut()
    }

    /// Loads the member's home and opens 今天 on it, or sign-up when they are in no squad.
    private func openHome(
        continuing signUp: SignUpModel? = nil, name: String? = nil, landingOn scene: SceneTheme? = nil
    ) async {
        // Only called once the account says who is signed in, so it is read from memory.
        guard case .signedIn(let member)? = try? await account.restore() else {
            await signedOut()
            return
        }
        let store = todayStore(of: member)
        await store.load()
        // Someone else signed in while it loaded: their own sign-in opens their home, and this
        // store's `signedOut` only means it was the earlier member's.
        guard case .signedIn(member)? = try? await account.restore() else { return }
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
        case .loading where store.home == nil, .offline where store.home == nil:
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
            // The case above has every load without a home.
            guard let home = store.home else { return }
            // The app was closed during sign-up, after 你的小队: carry on from the next step.
            if signUp == nil, let resumed = await resumedSignUp(in: home.squad.id) {
                screen = .signUp(resumed)
                return
            }
            // Signed up some other way since, or for another squad: nothing left to carry on.
            SignUpProgress.clear()
            await openTabs(on: home, store: store, landingOn: scene)
        }
    }

    /// 今天 under the tab bar, on the member's squad's home; on a picked scene the member drops
    /// onto it.
    private func openTabs(on home: Home, store: TodayStore, landingOn scene: SceneTheme?) async {
        let today = TodayModel(
            store: store, writer: APIDisclaimerWriter(api: api, fallback: DiceDisclaimerWriter()), posted: posted)
        let profile = MeModel(
            service: APIMeService(api: api, beforeDeleting: { try? await Push.registration.signingOut() }),
            confirm: confirmDeletion, signOut: { [weak self] in await self?.signOut() })
        let squad = SquadSettingsModel(
            service: APISquadSettingsService(api: api),
            changed: { [weak self] in Task { await self?.squadChanged() } },
            signOut: { [weak self] in await self?.signOut() })
        let schedule = ScheduleModel(store: ScheduleStore(backend: APIScheduleBackend(api: api), now: { Date() }))
        let recap = RecapShelf(
            service: APIWeekStoryService(api: api), squad: { store.home.map(RecapShelf.Squad.init) },
            scenePicker: { [api] story in await Self.scenePicker(api: api, after: story) },
            scenePicked: { [weak self] _ in Task { await self?.squadChanged() } })
        // The home loads after the reveal, which holds the scene meanwhile, so the drop counts
        // from now rather than from when the scene covered the screen.
        if let scene {
            await today.dropIn(on: scene, coveredAt: .now)
        } else if let read = await withLaunchCover({ await openingScene(of: home.squad.id) }) {
            // The loading screen stays up until the squad's scene is known, so 今天 never shows
            // the gym first and then switches.
            today.scene = read
        } else {
            // Slow or offline: the scene this phone kept, read again once the tabs are up.
            today.scene = KeptScene.scene(of: home.squad.id) ?? .gym
            Task { await readScene(of: home.squad.id, into: today) }
        }
        screen = .tabs(
            today: today, profile: profile, schedule: schedule, feed: Self.feed(api: api, home: home), squad: squad,
            recap: recap)
        homeSquad = home.squad.id
    }

    /// The member's home, from what the phone kept for them alone.
    private func todayStore(of member: MemberID) -> TodayStore {
        let directory = folders.folder(for: member)
        return TodayStore(
            backend: APICheckInBackend(api: memberAPI(member), directory: directory, shared: shared),
            outbox: DeviceOutbox(directory: directory),
            now: { Date() }, newID: { UUID() })
    }

    /// The squad's name or scene changed on 小队设置: 今天 and 我 read them again.
    private func squadChanged() async {
        guard case .tabs(let today, let profile, _, _, let squad, _) = screen else { return }
        await readScene(of: squad.settings?.squad.id, into: today)
        await today.load()
        await profile.reload()
    }

    /// 冠军专属 on a 战报's last page: when the reader picks the scene for the week after the
    /// story's and nobody has yet. Offline, there is no sticker.
    private static func scenePicker(api: WildcardAPI, after story: WeekStory) async -> ScenePicker? {
        guard let scene = try? await api.scene(of: story.squad), scene.canPick, scene.picked == nil,
            scene.week == story.week.monday.adding(days: 7)
        else { return nil }
        return ScenePicker(
            options: SceneOption.options(from: scene.history),
            service: APIScenePickService(api: api, squad: story.squad, week: scene.week))
    }

    /// 动态 on the member's squad, its days by the member's own clock.
    private static func feed(api: WildcardAPI, home: Home) -> FeedModel {
        let zone = home.timeZone
        let store = FeedStore(
            source: APIFeedSource(api: api), squad: home.squad.id, viewer: home.member,
            today: { LocalDay(at: Date(), in: zone) }, now: { Timestamp(Date()) })
        return FeedModel(store: store, viewer: home.member, now: { Date() })
    }

    private func registerForPush() async {
        try? await Push.registration.signedIn(APIDeviceRegistry(api: api))
    }

    private func signedOut() async {
        SignUpProgress.clear()
        KeptScene.forgetAll()
        folders.forgetAll()
        shared?.forget()
        if case .signUp(let model) = screen, model.step == .welcome { return }
        screen = .signUp(newSignUp(hasAgreedToAI: false))
    }

    /// The sign-up the app was closed during, carried on, when it had joined or made `squad`.
    private func resumedSignUp(in squad: SquadID) async -> SignUpModel? {
        guard let progress = SignUpProgress.saved, progress.squad == squad else { return nil }
        let model = newSignUp(hasAgreedToAI: true)
        return await model.resume(in: squad, madeIt: progress.madeIt) ? model : nil
    }

    private func newSignUp(hasAgreedToAI: Bool) -> SignUpModel {
        SignUpModel(
            service: APISignUpService(api: api), invite: nil, nickname: "", now: Date(), hasAgreedToAI: hasAgreedToAI)
    }
}

/// The squad's scene, which 今天 must open on rather than switch to.
extension AppModel {
    /// Puts 今天 on the squad's scene this week. Offline, it stays where it is.
    private func readScene(of squad: SquadID?, into today: TodayModel) async {
        guard let squad, let scene = await serverScene(of: squad) else { return }
        today.scene = scene
    }

    /// The squad's scene this week from the server, unless it takes longer than `Self.sceneWait`.
    private func openingScene(of squad: SquadID) async -> SceneTheme? {
        let wait = Self.sceneWait
        return await withTaskGroup(of: SceneTheme?.self) { group in
            group.addTask { await self.serverScene(of: squad) }
            group.addTask {
                try? await Task.sleep(for: wait)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Runs `work` under the launch cover: signing in on the open screen waits here too, for a
    /// member whose squad is already set up, rather than sitting on a button that seems to do
    /// nothing.
    private func withLaunchCover<Value>(_ work: () async -> Value) async -> Value {
        guard case .signUp = screen else { return await work() }
        screen = .starting
        openingUnderCover = true
        defer { openingUnderCover = false }
        return await work()
    }

    /// The squad's scene this week from the server, kept on this phone for the next launch.
    private func serverScene(of squad: SquadID) async -> SceneTheme? {
        guard let read = try? await api.scene(of: squad) else { return nil }
        let scene = SceneTheme(rawValue: read.scene.rawValue) ?? .gym
        KeptScene.save(scene, of: squad)
        return scene
    }

    /// How long the loading screen waits for the squad's scene before opening on the kept one.
    private static let sceneWait = Duration.seconds(3)
}
