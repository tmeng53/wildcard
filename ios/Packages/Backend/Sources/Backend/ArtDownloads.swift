import AvatarArt
import AvatarDomain
import Contracts
import Foundation

#if canImport(CryptoKit)
import CryptoKit
#endif

/// Keeps the art the API serves over the bundled art (the catalog's `art`) on this phone, where
/// `AvatarArt`'s `ArtTree` reads it. The standard pattern for content shipped apart from the
/// app: each file is downloaded once, by the content's SHA-256, and kept for good; a generation
/// is checked whole (size, hash, and that the art parses) and swapped in at once, so a screen
/// never draws half of a change; until then, and whenever anything fails, the art already here
/// stays. Nothing in it is the member's, so it stays on sign-out.
public actor ArtDownloads {
    private let root: URL
    private let fetch: @Sendable (URL) async throws -> Data
    private let digest: @Sendable (Data) -> String

    /// - Parameters:
    ///   - root: the folder whose `current` `ArtTree` reads (Application Support's `Art`).
    ///   - fetch: downloads one file.
    ///   - digest: a file's SHA-256 in lowercase hex.
    public init(
        root: URL = ArtTree.downloaded.deletingLastPathComponent(),
        fetch: @escaping @Sendable (URL) async throws -> Data,
        digest: (@Sendable (Data) -> String)? = nil
    ) {
        self.root = root
        self.fetch = fetch
        self.digest = digest ?? Self.sha256
    }

    /// Brings the art on this phone to `manifest`: downloads the files it lacks, checks them,
    /// and swaps the tree. Leaves out files a newer rig draws. Answers whether the art changed;
    /// false when it was current or anything failed, which the next call tries again.
    @discardableResult
    public func update(to manifest: ArtManifest) async -> Bool {
        guard manifest.generation != kept() else { return false }
        let files = manifest.files.filter { $0.rigVersion <= ArtTree.rigVersion && Self.isInTree($0.path) }
        var blobs: [(file: ArtManifest.File, at: URL)] = []
        for file in files {
            guard let blob = await blob(file, from: manifest.baseURL) else { return false }
            blobs.append((file, blob))
        }
        let next = root.appending(path: "next-\(UUID().uuidString)")
        do {
            for (file, blob) in blobs {
                let place = next.appending(path: file.path)
                try FileManager.default.createDirectory(
                    at: place.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: blob, to: place)
            }
            try FileManager.default.createDirectory(at: next, withIntermediateDirectories: true)
            // Two renames in one folder, each atomic: a crash between them leaves no `current`,
            // so the bundled art shows and the next launch downloads the generation again.
            let current = root.appending(path: "current")
            let old = root.appending(path: "next-old-\(UUID().uuidString)")
            if FileManager.default.fileExists(atPath: current.path(percentEncoded: false)) {
                try FileManager.default.moveItem(at: current, to: old)
            }
            try FileManager.default.moveItem(at: next, to: current)
            try JSONEncoder().encode(Kept(version: 1, generation: manifest.generation))
                .write(to: root.appending(path: "generation.json"), options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: next)
            return false
        }
        prune(keeping: Set(files.map { $0.name }))
        return true
    }

    /// The generation the tree holds; nil before the first.
    private func kept() -> Int? {
        guard FileManager.default.fileExists(atPath: root.appending(path: "current").path(percentEncoded: false)),
            let data = try? Data(contentsOf: root.appending(path: "generation.json")),
            let kept = try? JSONDecoder().decode(Kept.self, from: data), kept.version == 1
        else { return nil }
        return kept.generation
    }

    /// `file` on the phone, downloaded and checked if it wasn't; nil when it can't be had.
    private func blob(_ file: ArtManifest.File, from base: URL?) async -> URL? {
        let blobs = root.appending(path: "blobs")
        let place = blobs.appending(path: file.name)
        // Kept from an earlier generation: checked when it came, so only its size is looked at.
        if let kept = try? FileManager.default.attributesOfItem(atPath: place.path(percentEncoded: false))[.size]
            as? Int, kept == file.size
        {
            return place
        }
        guard let base, let data = try? await fetch(base.appending(path: file.name)),
            data.count == file.size, digest(data) == file.sha256, Self.isArt(data, at: file.path)
        else { return nil }
        do {
            try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
            try data.write(to: place, options: .atomic)
            return place
        } catch {
            return nil
        }
    }

    /// Removes downloaded files no longer in the art, and leftovers of a swap that didn't finish.
    private func prune(keeping names: Set<String>) {
        let blobs = root.appending(path: "blobs")
        for name in (try? FileManager.default.contentsOfDirectory(atPath: blobs.path(percentEncoded: false))) ?? []
        where !names.contains(name) {
            try? FileManager.default.removeItem(at: blobs.appending(path: name))
        }
        for name in (try? FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false))) ?? []
        where name.hasPrefix("next-") {
            try? FileManager.default.removeItem(at: root.appending(path: name))
        }
    }

    /// Whether `path` stays inside the art tree, whatever the server sent.
    static func isInTree(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return ["avatar", "coaches", "scenes"].contains(parts.first.map(String.init) ?? "")
            && parts.count > 1 && !parts.contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }

    /// Whether `data` reads as the art `path` holds: SVG this build's parser draws, JSON, or a PNG.
    static func isArt(_ data: Data, at path: String) -> Bool {
        if path.hasSuffix(".svg") {
            guard let svg = String(data: data, encoding: .utf8) else { return false }
            return (try? Artwork.read(svg: svg, path: path)) != nil
        }
        if path.hasSuffix(".json") { return (try? JSONSerialization.jsonObject(with: data)) is [String: Any] }
        if path.hasSuffix(".png") { return data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) }
        return false
    }

    private static let sha256: @Sendable (Data) -> String = { data in
        #if canImport(CryptoKit)
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        // Linux builds run tests only, and the tests pass their own digest.
        ""
        #endif
    }
}

/// Which generation the downloaded tree holds. Stored JSON, so it carries a `version`.
private struct Kept: Codable {
    let version: Int
    let generation: Int
}
