import Foundation

/// What this phone remembers of the member's new pieces (Tracy, 2026-11-04): which claimed
/// pieces they have tapped in their wardrobe since (NEW until then), and which waiting pieces
/// 商店街 has shown (我's shopfront dot clears then). Kept on the phone only:
/// another phone shows NEW again; what is claimed is the server's.
@MainActor
public protocol WardrobeMarks: AnyObject {
    var seen: Set<String> { get }
    var noticed: Set<String> { get }
    func see(_ piece: String)
    func notice(_ pieces: Set<String>)
}

/// Marks kept in memory, for previews, tests and sign-up, which forgets them on leaving.
@MainActor
public final class MemoryWardrobeMarks: WardrobeMarks {
    public private(set) var seen: Set<String>
    public private(set) var noticed: Set<String>

    public init(seen: Set<String> = [], noticed: Set<String> = []) {
        (self.seen, self.noticed) = (seen, noticed)
    }

    public func see(_ piece: String) { seen.insert(piece) }
    public func notice(_ pieces: Set<String>) { noticed.formUnion(pieces) }
}

/// Marks kept in the app's defaults, one list each per member.
@MainActor
public final class DeviceWardrobeMarks: WardrobeMarks {
    private let defaults: UserDefaults
    private let seenKey: String
    private let noticedKey: String

    public init(member: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        (seenKey, noticedKey) = ("wardrobe.seen.\(member)", "wardrobe.noticed.\(member)")
    }

    public var seen: Set<String> { Set(defaults.stringArray(forKey: seenKey) ?? []) }
    public var noticed: Set<String> { Set(defaults.stringArray(forKey: noticedKey) ?? []) }

    public func see(_ piece: String) {
        defaults.set(seen.union([piece]).sorted(), forKey: seenKey)
    }

    public func notice(_ pieces: Set<String>) {
        defaults.set(noticed.union(pieces).sorted(), forKey: noticedKey)
    }
}
