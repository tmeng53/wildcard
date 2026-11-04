import Foundation

/// What this phone remembers of the member's new pieces: which boxes they opened, and which of
/// those they have tapped since, so a piece wears NEW until then (Tracy, 2026-11-04). Kept on the
/// phone only: another phone shows the boxes again.
@MainActor
public protocol WardrobeMarks: AnyObject {
    var opened: Set<String> { get }
    var seen: Set<String> { get }
    func open(_ pieces: Set<String>)
    func see(_ piece: String)
}

/// Marks kept in memory, for previews, tests and sign-up, which forgets them on leaving.
@MainActor
public final class MemoryWardrobeMarks: WardrobeMarks {
    public private(set) var opened: Set<String>
    public private(set) var seen: Set<String>

    public init(opened: Set<String> = [], seen: Set<String> = []) {
        (self.opened, self.seen) = (opened, seen)
    }

    public func open(_ pieces: Set<String>) { opened.formUnion(pieces) }
    public func see(_ piece: String) { seen.insert(piece) }
}

/// Marks kept in the app's defaults, one list each per member.
@MainActor
public final class DeviceWardrobeMarks: WardrobeMarks {
    private let defaults: UserDefaults
    private let openedKey: String
    private let seenKey: String

    public init(member: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        (openedKey, seenKey) = ("wardrobe.opened.\(member)", "wardrobe.seen.\(member)")
    }

    public var opened: Set<String> { Set(defaults.stringArray(forKey: openedKey) ?? []) }
    public var seen: Set<String> { Set(defaults.stringArray(forKey: seenKey) ?? []) }

    public func open(_ pieces: Set<String>) {
        defaults.set(opened.union(pieces).sorted(), forKey: openedKey)
    }

    public func see(_ piece: String) {
        defaults.set(seen.union([piece]).sorted(), forKey: seenKey)
    }
}
