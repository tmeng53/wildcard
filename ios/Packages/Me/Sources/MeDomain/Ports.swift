import Contracts

/// How 我 reaches the member's account. An adapter talks to the API; previews and UI tests use
/// one in memory.
public protocol MeService: Sendable {
    func overview() async throws(MeError) -> MeOverview
    /// Saves the character after the member edits it in the character editor.
    func save(_ character: MeCharacter) async throws(MeError)
    /// Saves the number the member picked for their player card.
    func save(jerseyNumber: JerseyNumber) async throws(MeError)
    func setDailyPush(_ isOn: Bool) async throws(MeError)
    /// Turns the coach's pushes (教练消息) on or off; 通知 keeps what it says either way.
    func setCoachPush(_ isOn: Bool) async throws(MeError)
    /// Wears one of the member's titles on their card (nil: the latest won again); answers the
    /// board as it now stands.
    func equip(_ title: String?) async throws(MeError) -> TitleBoard
    /// 领取: puts an unlocked piece in the member's wardrobe. Safe to repeat.
    func claim(piece: String) async throws(MeError)
    /// Deletes the account and everything that is the member's, for good. Signing out on this phone
    /// is the app's to do after.
    func deleteAccount(_ confirmation: DeletionConfirmation) async throws(MeError)
}

/// How a squadmate's player card is read, for the sheet a teammate's name opens.
public protocol SquadmateCards: Sendable {
    func card(of member: MemberID, in squad: SquadID) async throws(MeError) -> PlayerCardFace
}

/// How the member confirmed deleting their account. Someone who signs in with Apple confirms
/// with Apple again, so the API can revoke the app's Apple tokens with the fresh code.
public enum DeletionConfirmation: Hashable, Sendable {
    case apple(authorizationCode: String)
    /// Test members on local Supabase, who sign in with a password.
    case signedInSession
}

/// What can go wrong on 我, by what the member can do about it.
public enum MeError: Error, Hashable, Sendable {
    /// No connection, or the server is down: try again.
    case unavailable
    /// The session ended: sign in again.
    case signedOut
    /// Apple's confirmation was closed before it finished: nothing happened.
    case confirmationCanceled
    /// Apple didn't confirm (no code came back): try again.
    case confirmationFailed
    /// The server refused what was saved (such as a nickname it doesn't take).
    case rejected
}
