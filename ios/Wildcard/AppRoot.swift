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
    /// A post a comment's push asked to open before the tabs were up.
    @State private var postToOpen: CheckInID?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // A ZStack, not a Group, so the task below starts once and outlives screen changes.
        ZStack {
            switch app.screen {
            case .starting:
                LaunchCover()
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
                    myPosts: app.myPosts, notices: app.notices, squadmateCards: app.squadmateCards, selection: $tab
                ) {
                    Task { await app.leftSquad() }
                }
                .onAppear {
                    // A tap that launched the app came before the tabs.
                    let dailyPush = delegate.takeDailyPushTap()
                    if let destination = delegate.takeDestination() {
                        WildcardApp.open(destination, today: today, tab: $tab)
                    } else if dailyPush {
                        today.replayPatsOnMe()
                    }
                    if let post = postToOpen {
                        postToOpen = nil
                        tab = .feed
                        feed.openPage(post)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: TicketRock.fadeOut), value: app.isStarting)
        // Signing in on the open screen: the tickets rock over it until the next screen opens.
        .loadingCover(app.isSigningIn) { LaunchCover() }
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
            delegate.opened = { [app, delegate, $tab, $postToOpen] opened in
                switch opened {
                // 动态, where the member sees the new 战报's tile and opens it themselves.
                case .weeklyAwards:
                    $tab.wrappedValue = .feed
                    Task { await app.readRecapAgain() }
                // The post's own page, over 动态, with the new comment.
                case .comment(let post):
                    if case .tabs(_, _, _, let feed, _, _) = app.screen {
                        $tab.wrappedValue = .feed
                        feed.openPage(post)
                    } else {
                        // A tap that launched the app comes before the tabs, which open it.
                        $postToOpen.wrappedValue = post
                    }
                case .dailyProgress, .other:
                    // Before the tabs are up, they take the 6pm push's destination when they appear.
                    if case .tabs(let today, _, _, _, _, _) = app.screen {
                        WildcardApp.open(
                            delegate.takeDestination(), dailyPush: delegate.takeDailyPushTap(), today: today,
                            tab: $tab)
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
