import AvatarDomain
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

    /// The downloaded file at `path` within `tree` (`scenes`, for the home's pictures), if any;
    /// nil keeps the bundled one.
    public static func downloadedFile(_ path: String, in tree: String) -> URL? {
        let mine = downloaded.appending(path: tree).appending(path: path)
        return FileManager.default.fileExists(atPath: mine.path(percentEncoded: false)) ? mine : nil
    }

    /// The names in `folder` within `tree`, bundled and downloaded together, sorted.
    static func names(in folder: String, of tree: String, bundled: URL) -> [String] {
        let places = [bundled.appending(path: folder), downloaded.appending(path: tree).appending(path: folder)]
        let names = places.flatMap {
            (try? FileManager.default.contentsOfDirectory(atPath: $0.path(percentEncoded: false))) ?? []
        }
        return Set(names).filter { !$0.hasPrefix(".") }.sorted()
    }

    /// Whether `data` is art this build reads at `path` (`avatar/…`, `coaches/…`, `scenes/…`,
    /// `openings/…`, whose JSON this build doesn't read yet),
    /// read the way the screens will: SVG through the parser, each JSON file through its own
    /// decoder (the rig, clips, tones, holds, a coach's look, `editor.json`, `kits.json`), a PNG by its signature.
    /// A downloaded file that fails is left out, so its path keeps the bundled file.
    public static func reads(_ data: Data, at path: String) -> Bool {
        let name = path.split(separator: "/").last.map(String.init) ?? ""
        if path.hasSuffix(".png") { return data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) }
        if path.hasSuffix(".svg") {
            guard let svg = String(data: data, encoding: .utf8) else { return false }
            return (try? Artwork.read(svg: svg, path: path)) != nil
        }
        guard path.hasSuffix(".json") else { return false }
        let parts = path.split(separator: "/").map(String.init)
        switch name {
        case "rig.json": return (try? Rig.decode(data)) != nil
        case "editor.json": return parts == ["avatar", "editor.json"] && (try? EditorChoices.decode(data)) != nil
        case "kits.json": return parts == ["avatar", "kits.json"] && (try? SportKits.decode(data)) != nil
        case "tones.json": return (try? Tones.decode(data)) != nil
        case "hold.json": return Figure.readsHold(data)
        case "look.json": return parts.first == "coaches" && CoachCharacter.readsLook(data)
        default:
            let clipFolders: Set<String> = ["clips", "moves", "accents"]
            return parts.contains { clipFolders.contains($0) } && (try? Clip.decode(data)) != nil
        }
    }
}
