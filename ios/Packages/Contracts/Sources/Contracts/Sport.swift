import Foundation

/// A listed sport, by its id, such as `run`. The list itself (names, icon, category, order) is
/// data the API serves, `SportCatalog`, so it changes without an app release; the id is all the
/// app's code knows of a sport. Ids never change, and a listed sport is never removed.
public struct Sport: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    /// Nil for anything that can't be a sport's id: camelCase letters and digits, never
    /// `custom`, the wire's word for 其他.
    public init?(rawValue: String) {
        guard rawValue != "custom", rawValue.count <= 40, let first = rawValue.unicodeScalars.first,
            ("a"..."z").contains(first),
            rawValue.unicodeScalars.allSatisfy({
                $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0))
            })
        else { return nil }
        self.rawValue = rawValue
    }

    /// For ids the app's own art and samples name, such as a scene's stations.
    public init(stringLiteral id: String) { rawValue = id }
}

/// 其他: a sport the member names themselves.
public struct CustomSport: Hashable, Sendable {
    /// Characters, counted as people see them.
    public static let maxLength = 20

    public let name: String

    public init(_ name: String) throws(ContractsError) {
        switch NameText.check(name, maxLength: Self.maxLength) {
        case .success(let trimmed): self.name = trimmed
        case .failure(.notOneLine): throw .multilineCustomSport
        case .failure(.length(let length)): throw .customSportLength(length)
        case .failure(.invisible): throw .invisibleCustomSport
        }
    }
}

/// What a 练了 or a planned training day is: a listed sport or the member's own.
public enum Activity: Hashable, Sendable {
    case sport(Sport)
    case custom(CustomSport)
}
