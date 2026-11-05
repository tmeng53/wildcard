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
    /// Which build reads the tree: art this build couldn't read (a newer rig, a kind it doesn't
    /// know) is tried again once the app is updated.
    private let reader: String
    /// The update running now, which later calls wait on, so two never swap the tree at once.
    private var running: (id: UUID, task: Task<Bool, Never>)?

    /// - Parameters:
    ///   - root: the folder whose `current` `ArtTree` reads (Application Support's `Art`).
    ///   - fetch: downloads one file.
    ///   - digest: a file's SHA-256 in lowercase hex.
    ///   - build: this app's build, which art left out as unreadable is tried again after.
    public init(
        root: URL = ArtTree.downloaded.deletingLastPathComponent(),
        fetch: @escaping @Sendable (URL) async throws -> Data,
        digest: (@Sendable (Data) -> String)? = nil,
        build: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    ) {
        self.root = root
        self.fetch = fetch
        self.digest = digest ?? Self.sha256
        reader = "\(ArtTree.rigVersion)/\(build)"
    }

    /// Brings the art on this phone to `manifest`: downloads the files it lacks, checks them,
    /// and swaps the tree. Leaves out files a newer rig draws, and pieces this build can't read in
    /// full (their folders keep the bundled art). Answers whether the art changed; false when it was
    /// current or a file couldn't be downloaded whole, which the next call tries again.
    /// Calls made while one runs (launch and a return to the app at once) wait for it, then
    /// find the tree current; a manifest older than the tree's generation changes nothing.
    @discardableResult
    public func update(to manifest: ArtManifest) async -> Bool {
        while let other = running {
            _ = await other.task.value
            // Whoever sees it finish first clears it, so a waiter never spins on a finished task.
            if running?.id == other.id { running = nil }
        }
        let id = UUID()
        let task = Task { await self.bring(to: manifest) }
        running = (id, task)
        let changed = await task.value
        if running?.id == id { running = nil }
        return changed
    }

    private func bring(to manifest: ArtManifest) async -> Bool {
        if let kept = kept(), kept.generation > manifest.generation || kept == holding(manifest) { return false }
        let files = manifest.files.filter { $0.rigVersion <= ArtTree.rigVersion && Self.isInTree($0.path) }
        var blobs: [(file: ArtManifest.File, at: URL)] = []
        var unreadable: Set<String> = []
        for file in files {
            switch await blob(file, from: manifest.baseURL) {
            case .here(let blob): blobs.append((file, blob))
            case .unreadable: unreadable.insert(Self.unit(of: file.path))
            case .unavailable: return false
            }
        }
        // A piece is its folder's files together: one this build can't read leaves the whole
        // folder out, so the bundled piece (or none) stands, never half of one.
        blobs.removeAll { unreadable.contains(Self.unit(of: $0.file.path)) }
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
            try JSONEncoder().encode(holding(manifest))
                .write(to: root.appending(path: "generation.json"), options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: next)
            return false
        }
        prune(keeping: Set(files.map { $0.name }))
        return true
    }

    /// What the tree holds; nil before the first.
    private func kept() -> Kept? {
        guard FileManager.default.fileExists(atPath: root.appending(path: "current").path(percentEncoded: false)),
            let data = try? Data(contentsOf: root.appending(path: "generation.json")),
            let kept = try? JSONDecoder().decode(Kept.self, from: data), kept.version == Kept.current
        else { return nil }
        return kept
    }

    /// What the tree holds once it is brought to `manifest` by this build.
    private func holding(_ manifest: ArtManifest) -> Kept {
        Kept(version: Kept.current, generation: manifest.generation, reader: reader)
    }

    /// `file` on the phone, downloaded if it wasn't, and read the way the screens will.
    private func blob(_ file: ArtManifest.File, from base: URL?) async -> Blob {
        let blobs = root.appending(path: "blobs")
        let place = blobs.appending(path: file.name)
        if let data = try? Data(contentsOf: place), data.count == file.size, digest(data) == file.sha256 {
            return ArtTree.reads(data, at: file.path) ? .here(place) : .unreadable
        }
        guard let base, let data = try? await fetch(base.appending(path: file.name)),
            data.count == file.size, digest(data) == file.sha256
        else { return .unavailable }
        guard ArtTree.reads(data, at: file.path) else { return .unreadable }
        do {
            try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
            try data.write(to: place, options: .atomic)
            return .here(place)
        } catch {
            return .unavailable
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

    /// What stands or falls together: a character variant's folder (`avatar/art/<slot>/<variant>`),
    /// a coach's (`coaches/<coach>`), an opening's (`openings/<opening>`), else the file itself (a move, a scene picture).
    static func unit(of path: String) -> String {
        let parts = path.split(separator: "/")
        if parts.count > 4, parts[0] == "avatar", parts[1] == "art" { return parts[0..<4].joined(separator: "/") }
        // Moves every coach shares (`coaches/moves/<move>.json`) stand alone, like a member's.
        if parts.count > 2, parts[0] == "coaches" || parts[0] == "openings", parts[1] != "moves" {
            return parts[0..<2].joined(separator: "/")
        }
        return path
    }

    /// Whether `path` stays inside the art tree, whatever the server sent.
    static func isInTree(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return ["avatar", "coaches", "scenes", "openings"].contains(parts.first.map(String.init) ?? "")
            && parts.count > 1 && !parts.contains { $0.isEmpty || $0 == "." || $0 == ".." }
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

/// A file of the art, as `blob` found it.
private enum Blob {
    /// Downloaded and readable, kept at this place.
    case here(URL)
    /// Downloaded whole, but this build can't read it: left out, so its path keeps the bundled art.
    case unreadable
    /// Not downloaded whole (no network, or not what the list says): the generation waits.
    case unavailable
}

/// Which generation the downloaded tree holds, and which build read it. Stored JSON, so it
/// carries a `version`.
private struct Kept: Codable, Equatable {
    static let current = 2
    let version: Int
    let generation: Int
    let reader: String
}
