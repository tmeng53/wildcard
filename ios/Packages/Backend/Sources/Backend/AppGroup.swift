import Foundation

/// What the app shares with its 6pm push view (a notification content extension, a separate
/// process): the sign-in, in the Keychain under this group, and a file of the squad's looks and
/// the place to open, in the group's container. Both are readable once the phone was unlocked
/// after a restart, so the push opens on a locked phone.
public enum AppGroup {
    public static let id = "group.com.wildcardsquad.wildcard"

    /// The group's container; nil when the build isn't signed into the group (the Linux tests).
    public static var directory: URL? {
        #if canImport(Darwin)
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
        #else
        nil
        #endif
    }

    /// Settings both processes read and write.
    public static var defaults: UserDefaults? { UserDefaults(suiteName: id) }
}
