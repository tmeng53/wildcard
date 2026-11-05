import Foundation

/// What this phone remembers of the member's new pieces (Tracy, 2026-11-04): which boxes they
/// opened, which claimed pieces they have tapped in their wardrobe since (NEW until then), and
/// which waiting pieces 商店街 has shown (我's shopfront dot clears then). Kept on the phone only:
/// another phone shows the boxes and NEW again; what is claimed is the server's.
@MainActor
public protocol WardrobeMarks: AnyObject {
    var opened: Set<String> { get }
    var seen: Set<String> { get }
    var noticed: Set<String> { get }
    func open(_ pieces: Set<String>)
    func see(_ piece: String)
    func notice(_ pieces: Set<String>)
}

/// Marks kept in memory, for previews, tests and sign-up, which forgets them on leaving.
@MainActor
public final class MemoryWardrobeMarks: WardrobeMarks {
    public private(set) var opened: Set<String>
    public private(set) var seen: Set<String>
    public private(set) var noticed: Set<String>

    public init(opened: Set<String> = [], seen: Set<String> = [], noticed: Set<String> = []) {
        (self.opened, self.seen, self.noticed) = (opened, seen, noticed)
    }

    public func open(_ pieces: Set<String>) { opened.formUnion(pieces) }
    public func see(_ piece: String) { seen.insert(piece) }
    public func notice(_ pieces: Set<String>) { noticed.formUnion(pieces) }
}

/// Marks kept in the app's defaults, one list each per member.
@MainActor
public final class DeviceWardrobeMarks: WardrobeMarks {
    private let defaults: UserDefaults
    private let openedKey: String
    private let seenKey: String
    private let noticedKey: String

    public init(member: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        (openedKey, seenKey, noticedKey) = (
            "wardrobe.opened.\(member)", "wardrobe.seen.\(member)", "wardrobe.noticed.\(member)"
        )
    }

    public var opened: Set<String> { Set(defaults.stringArray(forKey: openedKey) ?? []) }
    public var seen: Set<String> { Set(defaults.stringArray(forKey: seenKey) ?? []) }
    public var noticed: Set<String> { Set(defaults.stringArray(forKey: noticedKey) ?? []) }

    public func open(_ pieces: Set<String>) {
        defaults.set(opened.union(pieces).sorted(), forKey: openedKey)
    }

    public func see(_ piece: String) {
        defaults.set(seen.union([piece]).sorted(), forKey: seenKey)
    }

    public func notice(_ pieces: Set<String>) {
        defaults.set(noticed.union(pieces).sorted(), forKey: noticedKey)
    }
}
