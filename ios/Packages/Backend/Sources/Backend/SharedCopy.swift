import Contracts
import Foundation

/// The lines put over the app's String Catalog (`AppCopy`, the catalog's `appCopy` section), kept
/// where the app's extensions read them too: the push service writes a push's words from its
/// `loc-key`, so a line put shows in pushes as in the app. The app writes it from the catalog it
/// has on each launch and each fresh read; nothing in it is the member's, so it stays on sign-out.
public struct SharedCopy: Sendable {
    private let file: URL

    /// - Parameter directory: the app group's container (`AppGroup.directory`), or a test's own.
    public init(directory: URL) {
        file = directory.appending(path: "copy.json")
    }

    /// The app group's; nil when the build isn't signed into the group.
    public static var inAppGroup: SharedCopy? { AppGroup.directory.map(SharedCopy.init) }

    /// Keeps `copy` for the next launch of the app and its extensions.
    public func save(_ copy: AppCopy) {
        guard read() != copy, let data = try? JSONEncoder().encode(copy) else { return }
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Readable from the first unlock on, as the push service runs while the phone is locked.
        #if os(iOS)
        try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try? data.write(to: file, options: .atomic)
        #endif
    }

    /// The copy last kept; nil before the app first kept one, or in a shape this build can't read.
    public func read() -> AppCopy? {
        guard let data = try? Data(contentsOf: file), let copy = try? JSONDecoder().decode(AppCopy.self, from: data),
            copy.version == AppCopy.currentVersion
        else { return nil }
        return copy
    }
}
