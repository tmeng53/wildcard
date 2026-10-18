import Foundation

/// A typed UUID, so a member id can't be passed where a check-in id is expected.
/// Encodes as a bare UUID string.
public struct ID<Tag>: Hashable, Sendable, Codable, CustomStringConvertible {
    public let uuid: UUID

    public init(_ uuid: UUID) { self.uuid = uuid }

    public init(from decoder: Decoder) throws {
        uuid = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(uuid)
    }

    public var description: String { uuid.uuidString.lowercased() }
}

public enum MemberTag {}
public enum SquadTag {}
public enum CheckInTag {}

public typealias MemberID = ID<MemberTag>
public typealias SquadID = ID<SquadTag>
public typealias CheckInID = ID<CheckInTag>
