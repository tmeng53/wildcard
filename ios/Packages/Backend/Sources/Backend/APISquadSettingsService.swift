import Contracts
import DesignSystem
import Foundation
import ScenePickDomain
import SquadDomain

/// 小队设置 over our API: the member's first squad with its members' characters and the week's
/// scene, and the captain's changes, leaving and the scene pick.
public struct APISquadSettingsService: SquadSettingsService {
    private let api: WildcardAPI

    public init(api: WildcardAPI) {
        self.api = api
    }

    public func settings() async throws(SquadError) -> SquadSettings {
        try await squad { () throws(APIError) in
            let viewer = try await api.me().id
            guard let first = try await api.mySquads().first else { throw .refused(.squadNotJoined) }
            let today = try await api.today(of: first.id)
            let scene = try await api.scene(of: first.id)
            var characters: [MemberID: MemberCharacter] = [:]
            for mate in today.members {
                if let character = mate.character { characters[mate.member] = character }
            }
            return SquadSettings(squad: first, viewer: viewer, characters: characters, scene: scene)
        }
    }

    public func rename(_ squad: SquadID, to name: SquadName) async throws(SquadError) -> Squad {
        try await self.squad { () throws(APIError) in try await api.rename(squad, to: name) }
    }

    public func handCaptaincy(of squad: SquadID, to member: MemberID) async throws(SquadError) -> Squad {
        try await self.squad { () throws(APIError) in try await api.handCaptaincy(of: squad, to: member) }
    }

    public func remove(_ member: MemberID, from squad: SquadID) async throws(SquadError) {
        try await self.squad { () throws(APIError) in try await api.remove(member, from: squad) }
    }

    public func pick(_ scene: SceneID, for squad: SquadID, week: LocalDay) async throws(SquadError) -> SquadScene {
        try await self.squad { () throws(APIError) in try await api.pick(scene, for: squad, week: week) }
    }

    private func squad<T>(_ call: () async throws(APIError) -> T) async throws(SquadError) -> T {
        do {
            return try await call()
        } catch .account(.signedOut), .account(.credentialRejected) {
            throw .signedOut
        } catch .refused(.squadNotJoined) {
            throw .noSquad
        } catch .refused, .unreadableResponse {
            throw .outdated
        } catch {
            throw .unavailable
        }
    }
}

/// The scene picker on the 战报's last page, over our API: it picks for one squad and the week
/// open when the page was read.
public struct APIScenePickService: ScenePickService {
    private let api: WildcardAPI
    private let squad: SquadID
    private let week: LocalDay

    public init(api: WildcardAPI, squad: SquadID, week: LocalDay) {
        (self.api, self.squad, self.week) = (api, squad, week)
    }

    public func pick(_ scene: SceneTheme) async throws(ScenePickError) {
        guard let id = SceneID(rawValue: scene.rawValue) else { throw .notAllowed }
        do {
            _ = try await api.pick(id, for: squad, week: week)
        } catch .refused {
            throw .notAllowed
        } catch {
            throw .unavailable
        }
    }
}
