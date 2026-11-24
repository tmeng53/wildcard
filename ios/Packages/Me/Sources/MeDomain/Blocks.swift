import Contracts
import Foundation
import Observation

/// A teammate the member blocked (拉黑), as 设置 › 已拉黑 lists them.
public struct BlockedMember: Hashable, Sendable, Identifiable {
    public let id: MemberID
    /// Nil for one who never made their character.
    public let character: MeCharacter?
    public let since: Date

    public init(id: MemberID, character: MeCharacter?, since: Date) {
        (self.id, self.character, self.since) = (id, character, since)
    }
}

/// 设置 › 已拉黑: whom the member blocked, newest first, and 解除, which shows them to each other
/// again at once. The row in 设置 shows only once someone is on the list.
@MainActor @Observable
public final class BlockedMembersModel {
    public private(set) var blocked: [BlockedMember] = []
    /// The last read or 解除 didn't go through.
    public private(set) var failed = false

    @ObservationIgnored private let service: any MeService

    public init(service: any MeService) {
        self.service = service
    }

    /// Reads the list again; a failed read keeps what was read before.
    public func load() async {
        do {
            blocked = try await service.blocked()
            failed = false
        } catch {
            failed = true
        }
    }

    /// 解除: they leave the list once the server took it.
    public func unblock(_ member: MemberID) async {
        do {
            try await service.unblock(member)
            blocked.removeAll { $0.id == member }
            failed = false
        } catch {
            failed = true
        }
    }
}
