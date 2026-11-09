import AccountDomain
import AccountUI
import AppIntents
import Backend
import CheckInDomain
import Contracts
import DesignSystemUI
import Foundation
import HomeWidgetDomain
import HomeWidgetUI
import SportsUI
import WidgetKit

/// One moment of a widget: the board then, or why there is none.
struct BoardEntry: TimelineEntry {
    let date: Date
    let state: WidgetState
}

/// The widgets have nothing to set; WidgetKit's async provider needs an intent all the same.
struct BoardIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Wildcard"
}

/// Reads the squad for the widgets: the home over our API, signed in with the app's shared
/// session, or the copy the widget kept when the network fails. The app also asks the widgets
/// to read again whenever it leaves the screen, so a post shows at once.
struct BoardProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BoardEntry {
        Self.sample(at: Date())
    }

    func snapshot(for configuration: BoardIntent, in context: Context) async -> BoardEntry {
        context.isPreview ? Self.sample(at: Date()) : await Self.read(at: Date()).entry
    }

    func timeline(for configuration: BoardIntent, in context: Context) async -> Timeline<BoardEntry> {
        let (entry, zone) = await Self.read(at: Date())
        let next =
            entry.state == .unavailable
            ? entry.date.addingTimeInterval(WidgetState.retryInterval)
            : WidgetBoard.nextLook(after: entry.date, in: zone)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private static func sample(at now: Date) -> BoardEntry {
        BoardEntry(date: now, state: .board(SampleBoard.board(on: LocalDay(at: now, in: .current))))
    }

    /// Nobody signed in, or the session can't be renewed any more: the copy goes with them.
    private static func signedOut(at now: Date, folders: MemberFolders) -> (entry: BoardEntry, zone: TimeZone) {
        folders.forgetAll()
        return (BoardEntry(date: now, state: .signedOut), .current)
    }

    /// The board now, with the clock its day turns on.
    private static func read(at now: Date) async -> (entry: BoardEntry, zone: TimeZone) {
        // The language picked in the app, and the sports' icons from the list this build ships.
        AppLanguage.adopt(from: AppGroup.defaults, folder: AppGroup.directory)
        SportList.shared.show(CatalogClient.bundled.sports)
        // A build that names no backend (Debug) runs on the sample squad, as the app does.
        guard let address = BackendAddress(info: Bundle.main.infoDictionary ?? [:]) else {
            return (sample(at: now), .current)
        }
        let account = AccountSession(
            provider: SupabaseAuth(url: address.authURL, publishableKey: address.authPublishableKey),
            store: KeychainSessionStore(accessGroup: AppGroup.id), now: { Date() })
        let folders = MemberFolders(
            root: URL.applicationSupportDirectory.appending(path: "Widgets", directoryHint: .isDirectory))
        let state: AccountState
        do {
            state = try await account.restore()
        } catch {
            // The keychain is locked until the phone's first unlock after a restart, and so is the
            // widget's copy: try again soon, keeping the copy, rather than say nobody signed in.
            return (BoardEntry(date: now, state: .unavailable), .current)
        }
        guard case .signedIn(let member) = state else { return signedOut(at: now, folders: folders) }
        let backend = APICheckInBackend(
            api: WildcardAPI(
                url: address.apiURL, account: account, member: member, language: { AppLanguage.current.rawValue }),
            directory: folders.folder(for: member))
        let home: Home
        do {
            guard let read = try await backend.home() else { return (BoardEntry(date: now, state: .noSquad), .current) }
            home = read
        } catch .signedOut {
            return signedOut(at: now, folders: folders)
        } catch {
            guard let saved = await backend.savedHome() else {
                return (BoardEntry(date: now, state: .unavailable), .current)
            }
            home = saved
        }
        let coach = try? await backend.coach(in: home.squad.id)
        let hasNews = coach == nil ? false : ((try? await backend.hasUnseenCoachCards(in: home.squad.id)) ?? false)
        let board = WidgetBoard(
            home: home, day: LocalDay(at: now, in: home.timeZone), coach: coach?.coach.id, coachHasNews: hasNews)
        return (BoardEntry(date: now, state: .board(board)), home.timeZone)
    }
}
