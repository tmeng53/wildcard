import AccountDomain
import AccountUI
import Backend
import Contracts
import DesignSystemUI
import Foundation

/// The app's sign-in as the widgets use it: the session the app keeps in the Keychain under the
/// app group, and our API with it.
struct WidgetSession {
    /// What opening the session found.
    enum Opened {
        case signedIn(WidgetSession)
        case signedOut
        /// The Keychain can't be read now: the phone hasn't been unlocked since it restarted.
        case locked
        /// A build that names no backend (Debug): the sample squad.
        case sample
    }

    let member: MemberID
    let api: WildcardAPI

    /// The home over our API, keeping the widgets' own copy of it.
    var backend: APICheckInBackend { APICheckInBackend(api: api, directory: Self.folders.folder(for: member)) }

    /// Where the widgets keep their own copy of the home, one folder per member.
    static let folders = MemberFolders(
        root: URL.applicationSupportDirectory.appending(path: "Widgets", directoryHint: .isDirectory))

    static func open() async -> Opened {
        guard let address = BackendAddress(info: Bundle.main.infoDictionary ?? [:]) else { return .sample }
        let account = AccountSession(
            provider: SupabaseAuth(url: address.authURL, publishableKey: address.authPublishableKey),
            store: KeychainSessionStore(accessGroup: AppGroup.id), now: { Date() })
        let state: AccountState
        do {
            state = try await account.restore()
        } catch {
            return .locked
        }
        guard case .signedIn(let member) = state else { return .signedOut }
        let api = WildcardAPI(
            url: address.apiURL, account: account, member: member, language: { AppLanguage.current.rawValue })
        return .signedIn(WidgetSession(member: member, api: api))
    }
}
