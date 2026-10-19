import Contracts
import Foundation

/// A signed-in member's tokens, as the auth provider issued them.
public struct Session: Hashable, Sendable {
    public let member: MemberID
    /// Sent to our API as `Authorization: Bearer …`. Short-lived.
    public let accessToken: String
    /// Exchanged with the provider for a new session. Long-lived and single-use.
    public let refreshToken: String
    /// When `accessToken` stops being accepted.
    public let expiresAt: Date

    public init(member: MemberID, accessToken: String, refreshToken: String, expiresAt: Date) {
        self.member = member
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

/// How a session is kept on the device: JSON with its shape's `version` at the top.
public enum StoredSession {
    private struct Record: Codable {
        let version: Int
        let member: MemberID
        let accessToken: String
        let refreshToken: String
        /// Seconds since 1970, so the JSON needs no date strategy.
        let expiresAt: Double
    }

    private struct Version: Decodable {
        let version: Int
    }

    public static func encode(_ session: Session) throws(AccountError) -> Data {
        let record = Record(
            version: 1, member: session.member, accessToken: session.accessToken,
            refreshToken: session.refreshToken, expiresAt: session.expiresAt.timeIntervalSince1970)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            return try encoder.encode(record)
        } catch {
            throw .storeFailed
        }
    }

    public static func decode(_ data: Data) throws(AccountError) -> Session {
        let decoder = JSONDecoder()
        let version: Int
        do {
            version = try decoder.decode(Version.self, from: data).version
        } catch {
            throw .storeCorrupted
        }
        guard version == 1 else { throw .unsupportedVersion(version) }
        do {
            let record = try decoder.decode(Record.self, from: data)
            return Session(
                member: record.member, accessToken: record.accessToken, refreshToken: record.refreshToken,
                expiresAt: Date(timeIntervalSince1970: record.expiresAt))
        } catch {
            throw .storeCorrupted
        }
    }
}
