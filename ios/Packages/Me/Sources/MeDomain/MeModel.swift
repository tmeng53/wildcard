import Contracts
import Observation

/// Where 我 is while it reads the member's overview.
public enum MeLoad: Hashable, Sendable {
    case loading
    case loaded(MeOverview)
    case failed(MeError)
}

/// 我 on screen: the overview, the notification switch, signing out and deleting the account.
/// Changes save right away; a switch that fails to save flips back.
@MainActor @Observable
public final class MeModel {
    public private(set) var load: MeLoad = .loading
    public private(set) var deletion: DeletionPhase = .reading
    /// The 注销账号 page is open; it takes the whole screen, tab bar included.
    public private(set) var isDeletionOpen = false
    /// The last change didn't save (the switch flipped back, or the edited character stayed as
    /// it was); the screen says so until the next change.
    public private(set) var saveFailed = false

    @ObservationIgnored private let service: any MeService
    @ObservationIgnored private let confirm: @MainActor () async throws(MeError) -> DeletionConfirmation
    @ObservationIgnored private let signOutHere: @MainActor () async -> Void

    /// `confirm` asks the member to confirm deleting with Apple and hands back how they did;
    /// `signOut` signs out on this phone and takes the app back to its open screen.
    public init(
        service: any MeService,
        confirm: @escaping @MainActor () async throws(MeError) -> DeletionConfirmation,
        signOut: @escaping @MainActor () async -> Void
    ) {
        self.service = service
        self.confirm = confirm
        self.signOutHere = signOut
    }

    public var overview: MeOverview? {
        if case .loaded(let overview) = load { overview } else { nil }
    }

    /// Reads the overview, again after a failure or when the tab comes back.
    public func reload() async {
        do {
            let overview = try await service.overview()
            load = .loaded(overview)
        } catch {
            // Keep what is on screen when a refresh fails; say so only when there is nothing.
            if overview == nil { load = .failed(error) }
            await signOutIfEnded(error)
        }
    }

    public var dailyPushOn: Bool {
        overview?.dailyPushOn ?? false
    }

    /// Flips the daily push and saves it; flips back if saving fails.
    public func setDailyPush(_ isOn: Bool) async {
        guard case .loaded(var overview) = load, overview.dailyPushOn != isOn else { return }
        saveFailed = false
        overview.dailyPushOn = isOn
        load = .loaded(overview)
        do {
            try await service.setDailyPush(isOn)
        } catch {
            // Flip back only the switch: anything saved meanwhile (an edited character) stays.
            if case .loaded(var latest) = load {
                latest.dailyPushOn = !isOn
                load = .loaded(latest)
            }
            saveFailed = true
            await signOutIfEnded(error)
        }
    }

    /// Saves the character the member edited in the character editor, and shows it.
    public func save(_ character: MeCharacter) async {
        saveFailed = false
        do {
            try await service.save(character)
        } catch {
            saveFailed = true
            await signOutIfEnded(error)
            return
        }
        guard case .loaded(var overview) = load else { return }
        overview.character = character
        load = .loaded(overview)
    }

    /// Saves the number the member picked for their card, and shows it.
    public func save(jerseyNumber: JerseyNumber) async {
        saveFailed = false
        do {
            try await service.save(jerseyNumber: jerseyNumber)
        } catch {
            saveFailed = true
            await signOutIfEnded(error)
            return
        }
        guard case .loaded(var overview) = load else { return }
        overview.jerseyNumber = jerseyNumber
        load = .loaded(overview)
    }

    public func signOut() async {
        await signOutHere()
    }

    /// The 注销账号 page opens fresh each time.
    public func openDeletion() {
        deletion = .reading
        isDeletionOpen = true
    }

    /// Back to 我, unless the account is being deleted right now.
    public func closeDeletion() {
        guard deletion != .deleting else { return }
        isDeletionOpen = false
    }

    /// Confirms with Apple, then deletes the account. On success the account is gone, so this
    /// phone signs out and the app goes back to its open screen; closing Apple's sheet changes
    /// nothing.
    public func deleteAccount() async {
        guard deletion.canConfirm else { return }
        do {
            let confirmation = try await confirm()
            deletion = .deleting
            try await service.deleteAccount(confirmation)
            deletion = .deleted
        } catch {
            deletion = .after(error)
            await signOutIfEnded(error)
            return
        }
        await signOutHere()
    }

    /// A session that ended can't be renewed here: sign out, and the app asks to sign in again.
    private func signOutIfEnded(_ error: MeError) async {
        if error == .signedOut { await signOutHere() }
    }
}
