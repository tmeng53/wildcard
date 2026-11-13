import Contracts
import Foundation
import Observation

/// One of the accounts an admin switches between in 设置 › 管理员 › 演示账号 (Tracy,
/// 2026-11-13): their own, or a demo account they made for promo pictures, an ordinary member
/// they dress, post and squad up as.
public struct DemoAccount: Hashable, Sendable, Identifiable {
    public let id: MemberID
    /// The admin's own account, first in the list.
    public let isOwner: Bool
    /// Nil until the account made its character, at its sign-up.
    public let character: MeCharacter?

    public init(id: MemberID, isOwner: Bool, character: MeCharacter?) {
        (self.id, self.isOwner, self.character) = (id, isOwner, character)
    }
}

/// Where an admin's demo accounts are listed and made. Switching itself belongs to the app,
/// which holds the sign-in.
public protocol DemoAccountService: Sendable {
    /// The admin's own account, then their demo accounts, oldest first.
    func accounts() async throws(MeError) -> [DemoAccount]
    /// Makes a new, empty demo account.
    func create() async throws(MeError) -> MemberID
}

/// 演示账号 on screen: the accounts, which one this phone is on, switching to one and making a
/// new one to switch to. A switch that worked replaces the whole app, this page with it; one
/// that failed says so here and stays on the account it started from.
@MainActor @Observable
public final class DemoAccountsModel {
    public enum Phase: Hashable, Sendable {
        case loading
        case ready
        /// The list didn't load, or a switch or a new account failed: try again.
        case failed
        /// Switching to this account, or to a new one (nil) once it is made.
        case switching(MemberID?)
    }

    public private(set) var accounts: [DemoAccount] = []
    public private(set) var phase: Phase = .loading
    /// The account this phone is signed in on.
    public let current: MemberID

    @ObservationIgnored private let service: any DemoAccountService
    @ObservationIgnored private let switchTo: @MainActor (MemberID) async -> Bool
    @ObservationIgnored private let returnHome: @MainActor () async -> Bool

    /// - Parameters:
    ///   - switchTo: signs in on a demo account and opens it; false when that failed.
    ///   - returnHome: back on the admin's own account; false when that failed.
    public init(
        service: any DemoAccountService, current: MemberID,
        switchTo: @escaping @MainActor (MemberID) async -> Bool,
        returnHome: @escaping @MainActor () async -> Bool
    ) {
        self.service = service
        self.current = current
        self.switchTo = switchTo
        self.returnHome = returnHome
    }

    public var isSwitching: Bool {
        if case .switching = phase { return true }
        return false
    }

    public func load() async {
        do {
            accounts = try await service.accounts()
            phase = .ready
        } catch {
            phase = .failed
        }
    }

    /// Switches to `account`; the one this phone is on already does nothing.
    public func open(_ account: DemoAccount) async {
        guard account.id != current, !isSwitching else { return }
        phase = .switching(account.id)
        let switched = account.isOwner ? await returnHome() : await switchTo(account.id)
        phase = switched ? .ready : .failed
    }

    /// Makes a new demo account and switches to it, where it signs up like anyone.
    public func makeNew() async {
        guard !isSwitching else { return }
        phase = .switching(nil)
        do {
            let made = try await service.create()
            phase = await switchTo(made) ? .ready : .failed
        } catch {
            phase = .failed
        }
    }
}

/// An admin's demo accounts kept in memory: the sample member's and previews'.
public actor KeptDemoAccounts: DemoAccountService {
    public private(set) var kept: [DemoAccount]
    private let newID: @Sendable () -> MemberID

    public init(_ accounts: [DemoAccount], newID: @escaping @Sendable () -> MemberID) {
        kept = accounts
        self.newID = newID
    }

    public func accounts() async throws(MeError) -> [DemoAccount] { kept }

    public func create() async throws(MeError) -> MemberID {
        let id = newID()
        kept.append(DemoAccount(id: id, isOwner: false, character: nil))
        return id
    }
}
