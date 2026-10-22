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
            overview.dailyPushOn = !isOn
            load = .loaded(overview)
            saveFailed = true
        }
    }

    /// Saves the character the member edited in the character editor, and shows it.
    public func save(_ character: MeCharacter) async {
        saveFailed = false
        do {
            try await service.save(character)
        } catch {
            saveFailed = true
            return
        }
        guard case .loaded(var overview) = load else { return }
        overview.character = character
        load = .loaded(overview)
    }

    public func signOut() async {
        await signOutHere()
    }

    /// The 注销账号 page opens fresh each time.
    public func openDeletion() {
        deletion = .reading
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
            return
        }
        await signOutHere()
    }
}
