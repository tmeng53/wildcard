import Foundation

/// The app group the app and its extensions (the widgets, the push views) share, and its
/// container, where what every process reads lives: the downloaded art, the squad's looks, the
/// copy. Here, below every package, so art read by `AvatarArt` finds the same folder in each
/// process; `Backend`'s `AppGroup` adds the shared settings.
public enum SharedContainer {
    public static let appGroup = "group.com.wildcardsquad.wildcard"

    /// The group's container; nil when the build isn't signed into the group (the Linux tests).
    public static var directory: URL? {
        #if canImport(Darwin)
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        #else
        nil
        #endif
    }
}
