import Contracts
import Foundation

/// The captain's push about a request to join, as the server's `event` carries it (Tracy,
/// 2026-11-12): who asked, their note and their character, since they aren't a squadmate yet and
/// the app keeps no look for them. Long-pressed, the captain answers it there.
public struct JoinRequestPush: Hashable, Sendable {
    public let request: JoinRequestID
    public let squad: SquadID
    public let member: MemberID
    public let nickname: String
    /// What they wrote with the request, if anything.
    public let note: String?
    /// Their character; nil before they made one, which draws a stand-in.
    public let look: CharacterLook?

    /// Reads the push's `event`, as JSON.
    public init(event: Data) throws(DailyPushError) {
        guard let wire = try? JSONDecoder().decode(Wire.self, from: event), wire.kind == "joinRequest" else {
            throw .unreadable
        }
        request = wire.request
        squad = wire.squadId
        member = wire.member
        nickname = wire.nickname
        let note = wire.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = note?.isEmpty == false ? note : nil
        look = wire.look.map { CharacterLook(persona: $0.persona, variants: $0.variants, colors: $0.colors ?? [:]) }
    }

    private struct Wire: Decodable {
        let kind: String
        let squadId: SquadID
        let request: JoinRequestID
        let member: MemberID
        let nickname: String
        let note: String?
        let look: Look?
    }

    private struct Look: Decodable {
        let persona: String
        let variants: [String: String]
        let colors: [String: String]?
    }
}
