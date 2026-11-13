import APIContract
import AccountDomain
import AvatarArt
import AvatarDomain
import Contracts
import Foundation
import MeDomain

// An admin's demo accounts (Tracy, 2026-11-13): listing them, making one, and the refresh token
// that switches to one.
extension WildcardAPI {
    /// The admin's own account, then their demo accounts, oldest first.
    public func demoAccounts() async throws(APIError) -> [DemoAccount] {
        let wire = try await call { try await client.listDemoAccounts().ok.body.json }
        return try read { () throws(ContractsError) in
            try wire.accounts.map { account throws(ContractsError) in
                guard let id = UUID(uuidString: account.memberId) else { throw .invalidID(account.memberId) }
                let character = try account.character.map { wire throws(ContractsError) in try MemberCharacter(wire) }
                return DemoAccount(
                    id: MemberID(id), isOwner: account.owner,
                    character: character.map {
                        MeCharacter(nickname: $0.nickname.text, outfit: Outfit($0.look), persona: Persona($0.look))
                    })
            }
        }
    }

    /// Makes a new, empty demo account.
    public func createDemoAccount() async throws(APIError) -> MemberID {
        let made = try await call { try await client.createDemoAccount().created.body.json }
        guard let id = UUID(uuidString: made.memberId) else { throw .unreadableResponse }
        return MemberID(id)
    }

    /// The credential that signs in on one of the admin's demo accounts.
    public func handOff(to account: MemberID) async throws(APIError) -> Credential {
        let handOff = try await call {
            try await client.handOffDemoAccount(path: .init(memberId: account.description)).ok.body.json
        }
        return .handOff(refreshToken: handOff.refreshToken)
    }
}

/// 演示账号's list over our API.
public struct APIDemoAccountService: DemoAccountService {
    private let api: WildcardAPI

    public init(api: WildcardAPI) {
        self.api = api
    }

    public func accounts() async throws(MeError) -> [DemoAccount] {
        try await meCall { () throws(APIError) in try await api.demoAccounts() }
    }

    public func create() async throws(MeError) -> MemberID {
        try await meCall { () throws(APIError) in try await api.createDemoAccount() }
    }
}
