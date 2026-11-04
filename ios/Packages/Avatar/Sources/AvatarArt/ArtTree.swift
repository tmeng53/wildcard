import Foundation

/// The art tree the app draws from: the files this package bundles, with the ones downloaded
/// since (the API's catalog lists them; `Backend`'s `ArtDownloads` keeps them) standing in front.
/// Paths are the API's: `avatar/…` over the `Placeholder` folder, `coaches/…` over `Coaches`.
/// A path nothing was downloaded for reads the bundled file, so a phone that never downloaded
/// anything draws exactly what it shipped with.
public enum ArtTree {
    /// The rig this build draws. Downloaded art that needs a newer one is left out
    /// (`rigVersion` in the catalog), so new rig parts never break an older build.
    public static let rigVersion = 1

    /// Where the downloaded files stand, mirroring the tree's paths: Application Support's
    /// `Art/current`, swapped whole for a newer generation once all of it is downloaded.
    public static var downloaded: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return (support ?? FileManager.default.temporaryDirectory).appending(path: "Art/current")
    }

    /// The file at `path` within `tree` (`avatar`, `coaches`): the downloaded one, else `bundled`'s.
    static func url(_ path: String, in tree: String, bundled: URL) -> URL {
        let mine = downloaded.appending(path: tree).appending(path: path)
        return FileManager.default.fileExists(atPath: mine.path(percentEncoded: false))
            ? mine : bundled.appending(path: path)
    }

    /// The names in `folder` within `tree`, bundled and downloaded together, sorted.
    static func names(in folder: String, of tree: String, bundled: URL) -> [String] {
        let places = [bundled.appending(path: folder), downloaded.appending(path: tree).appending(path: folder)]
        let names = places.flatMap {
            (try? FileManager.default.contentsOfDirectory(atPath: $0.path(percentEncoded: false))) ?? []
        }
        return Set(names).filter { !$0.hasPrefix(".") }.sorted()
    }
}
