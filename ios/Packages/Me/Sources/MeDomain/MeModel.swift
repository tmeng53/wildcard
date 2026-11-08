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
    /// Pieces claimed here, saved or on their way: a claim is never taken back, so a read that left
    /// one out (it was on its way before the claim saved) still shows it claimed.
    @ObservationIgnored private var claimedHere: Set<String> = []
    @ObservationIgnored private let confirm: @MainActor () async throws(MeError) -> DeletionConfirmation
    @ObservationIgnored private let signOutHere: @MainActor () async -> Void
    /// Where 意见反馈 sends what the member writes us.
    @ObservationIgnored public let feedback: any FeedbackService

    /// `confirm` asks the member to confirm deleting with Apple and hands back how they did;
    /// `signOut` signs out on this phone and takes the app back to its open screen; `feedback`
    /// sends 意见反馈 (in memory unless one is given).
    public init(
        service: any MeService,
        confirm: @escaping @MainActor () async throws(MeError) -> DeletionConfirmation,
        signOut: @escaping @MainActor () async -> Void,
        feedback: any FeedbackService = KeptFeedback()
    ) {
        self.service = service
        self.feedback = feedback
        self.confirm = confirm
        self.signOutHere = signOut
    }

    public var overview: MeOverview? {
        if case .loaded(let overview) = load { overview } else { nil }
    }

    /// Reads the overview, again after a failure or when the tab comes back. A try after a
    /// failure shows the loader again, never the failure while it waits.
    public func reload() async {
        if case .failed = load { load = .loading }
        do {
            var overview = try await service.overview()
            overview.claimed.formUnion(claimedHere)
            load = .loaded(overview)
        } catch {
            // A read cut short (the tab left, the app went to the background) didn't fail: the
            // next one runs when the page is back.
            guard !Task.isCancelled else { return }
            // Keep what is on screen when a refresh fails; say so only when there is nothing.
            if overview == nil { load = .failed(error) }
            await signOutIfEnded(error)
        }
    }

    public var dailyPushOn: Bool {
        overview?.dailyPushOn ?? false
    }

    /// The coach's pushes (教练消息): its morning note and its replies, all silent.
    public var coachPushOn: Bool {
        overview?.coachPushOn ?? false
    }

    /// Flips the daily push and saves it; flips back if saving fails.
    public func setDailyPush(_ isOn: Bool) async {
        await flip(\.dailyPushOn, to: isOn) { isOn throws(MeError) in try await service.setDailyPush(isOn) }
    }

    /// Flips the coach's pushes and saves it; flips back if saving fails.
    public func setCoachPush(_ isOn: Bool) async {
        await flip(\.coachPushOn, to: isOn) { isOn throws(MeError) in try await service.setCoachPush(isOn) }
    }

    /// Shows a push switch flipped at once and saves it; flips it back if saving fails.
    private func flip(
        _ push: WritableKeyPath<MeOverview, Bool>, to isOn: Bool,
        save: (Bool) async throws(MeError) -> Void
    ) async {
        guard case .loaded(var overview) = load, overview[keyPath: push] != isOn else { return }
        saveFailed = false
        overview[keyPath: push] = isOn
        load = .loaded(overview)
        do {
            try await save(isOn)
        } catch {
            // Flip back only the switch: anything saved meanwhile (an edited character) stays.
            if case .loaded(var latest) = load {
                latest[keyPath: push] = !isOn
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

    /// The pieces that came to the member and aren't claimed yet: the unlocked ones and the ones
    /// the street holds as theirs (a limited store's starters while it is open). They wait in
    /// their stores on 商店街, marked NEW.
    public var unclaimed: [String] {
        guard let overview else { return [] }
        let unlocked = overview.unlocks.filter { $0.kind == .piece }.map(\.id)
        let owned = (overview.stock?.pieces ?? []).filter { $0.state == .owned }.map(\.id)
        var seen: Set<String> = []
        return (unlocked + owned).filter { !overview.claimed.contains($0) && seen.insert($0).inserted }
    }

    /// 领取: puts `piece` in the wardrobe at once and saves it; takes it out again if saving fails.
    /// Answers whether it was kept.
    @discardableResult
    public func claim(_ piece: String) async -> Bool {
        guard case .loaded(var overview) = load, !overview.claimed.contains(piece) else { return true }
        saveFailed = false
        overview.claimed.insert(piece)
        claimedHere.insert(piece)
        load = .loaded(overview)
        do {
            try await service.claim(piece: piece)
            return true
        } catch {
            claimedHere.remove(piece)
            if case .loaded(var latest) = load {
                latest.claimed.remove(piece)
                load = .loaded(latest)
            }
            saveFailed = true
            await signOutIfEnded(error)
            return false
        }
    }

    /// Wears `title` on the card's front at once (nil: the latest won again) and saves it; puts
    /// the one worn before back if saving fails.
    public func equip(_ title: String?) async {
        guard case .loaded(var overview) = load else { return }
        let before = overview.board
        saveFailed = false
        overview.board.worn = title ?? overview.board.titles.first?.title
        load = .loaded(overview)
        do {
            let board = try await service.equip(title)
            if case .loaded(var latest) = load {
                latest.board = board
                load = .loaded(latest)
            }
        } catch {
            if case .loaded(var latest) = load {
                latest.board = before
                load = .loaded(latest)
            }
            saveFailed = true
            await signOutIfEnded(error)
        }
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
