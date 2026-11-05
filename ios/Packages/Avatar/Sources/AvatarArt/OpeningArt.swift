import AvatarDomain
import Foundation

/// The full-screen openings admins draw (a holiday's 「感恩节快乐」), each a folder of
/// `timeline.json` and the SVGs it names in `openings/<id>/`: downloaded (`ArtTree`), else
/// bundled in `Openings/<id>/`. A takeover scene's opening has the scene's id, and plays the
/// first time a home shows that scene each day. One this build can't read is none: it's skipped.
public enum OpeningArt {
    /// An opening with its layers' art, ready to play.
    public struct Loaded: Sendable {
        public let opening: Opening
        /// Each `.art` layer's SVG, by file name.
        public let art: [String: Artwork]
    }

    /// The opening `id`, or nil when this build has none it can read.
    public static func load(_ id: String) -> Loaded? {
        guard isID(id), let data = try? Data(contentsOf: url(id, "timeline.json")),
            let opening = try? Opening.decode(data)
        else { return nil }
        var art: [String: Artwork] = [:]
        for file in Set(opening.artFiles) {
            guard let svg = try? String(contentsOf: url(id, file), encoding: .utf8),
                let artwork = try? Artwork.read(svg: svg, path: "openings/\(id)/\(file)")
            else { return nil }
            art[file] = artwork
        }
        return Loaded(opening: opening, art: art)
    }

    /// Ids are the API's: camelCase letters and digits, never a path.
    static func isID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 40 && id.first?.isLowercase == true
            && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    private static func url(_ id: String, _ file: String) -> URL {
        ArtTree.url("\(id)/\(file)", in: "openings", bundled: root)
    }

    /// The copied `Openings` folder inside this package's resource bundle.
    static var root: URL {
        (Bundle.module.resourceURL ?? Bundle.module.bundleURL).appendingPathComponent("Openings")
    }
}
