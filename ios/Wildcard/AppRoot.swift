import AccountUI
import CheckInUI
import Contracts
import DesignSystem
import DesignSystemUI
import FeedUI
import OnboardingUI
import SwiftUI

/// The app on the real backend: the screen its account is on.
struct AppRoot: View {
    let app: AppModel
    @Binding var tab: MainTabs.Tab
    let delegate: AppDelegate
    /// Where a tapped push goes (its notice's place), kept until the tabs open it.
    @State private var pushDestination: AppDestination?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // A ZStack, not a Group, so the task below starts once and outlives screen changes.
        ZStack {
            switch app.screen {
            case .starting where app.startsOffline:
                // Nothing kept on the phone to show and no server: say so, and keep trying.
                StateView.offline(retryIdentifier: "launch.retry") { app.retryStart() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(role: .bgCanvas, in: .gym))
                    .zIndex(1)
                    .transition(.opacity)
            case .starting:
                LaunchCover(start: app.coverSince)
                    // Over the screen that replaces it while it fades.
                    .zIndex(1)
                    .transition(.opacity)
            case .signUp(let signUp):
                SignUpView(model: signUp, privacyPolicy: PolicyPages.privacyPolicy, terms: PolicyPages.terms) {
                    SignInButton(app: app, signUp: signUp)
                } tabs: { showsBar, content in
                    MainTabs.entranceTabs(showsBar: showsBar, content: content)
                }
                .onChange(of: signUp.finished) { _, finished in
                    if finished != nil { Task { await app.finishSignUp(landingOn: signUp.landing) } }
                }
                .onChange(of: signUp.joinedSquad) { _, squad in
                    if let squad { SignUpProgress.save(squad: squad, madeIt: signUp.madeTheSquad) }
                }
            case .tabs(let today, let profile, let schedule, let feed, let squad, let recap):
                MainTabs(
                    today: today, profile: profile, schedule: schedule, feed: feed, squad: squad, recap: recap,
                    myPosts: app.myPosts, notices: app.notices, squadmateCards: app.squadmateCards, selection: $tab,
                    destination: $pushDestination
                ) {
                    Task { await app.leftSquad() }
                }
                .onAppear {
                    // A tap that launched the app came before the tabs.
                    if let destination = delegate.takeDestination() {
                        WildcardApp.open(destination, today: today, tab: $tab)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: TicketRock.fadeOut), value: app.isStarting)
        // Signing in on the open screen: the tickets rock over it until the next screen opens.
        .loadingCover(app.isSigningIn) { LaunchCover(start: app.coverSince) }
        .alert(
            Text("你已不在 \(app.lostSquadName ?? "") 小队"),
            isPresented: Binding(
                get: { app.lostSquadName != nil },
                set: { shown in if !shown { app.lostSquadName = nil } })
        ) {
            Button {
                app.lostSquadName = nil
            } label: {
                Text("确认")
            }
        }
        .task { await app.run() }
        // An invite link: universal links come here in a SwiftUI app.
        .onOpenURL { url in
            if let code = InviteLink.code(in: url) { app.open(invite: code) }
        }
        // Each account's tabs open on 今天, not where the last one left off (我, after signing out).
        .onChange(of: app.showsTabs) { _, shows in
            if !shows { tab = .today }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await app.refreshCatalog() }
                Task { await app.refreshScene() }
            }
        }
        .onAppear {
            delegate.opened = { [app, delegate, $tab, $pushDestination] opened in
                switch opened {
                // Where its notice in 通知 goes (MainTabs' `open`), unless the 6pm push's view
                // asked for 动态 or 打卡; before the tabs are up, they open it as they appear.
                case .open(let place) where !delegate.hasDestination:
                    $pushDestination.wrappedValue = place
                case .open, .other:
                    if case .tabs(let today, _, _, _, _, _) = app.screen {
                        WildcardApp.open(delegate.takeDestination(), today: today, tab: $tab)
                    }
                    Task { await app.reloadToday() }
                }
            }
        }
    }
}

/// The open screen's sign-in: Sign in with Apple, or in Debug with `-test-member` that member of
/// local Supabase.
private struct SignInButton: View {
    let app: AppModel
    let signUp: SignUpModel

    var body: some View {
        ContinueWithApple {
            Task {
                #if DEBUG
                if let member = LaunchOptions.testMember {
                    await app.signIn(
                        with: .testMember(email: member.email, password: member.password), name: nil, from: signUp)
                    return
                }
                #endif
                await app.signIn(await AppleSignIn.authorize(), from: signUp)
            }
        }
    }
}
